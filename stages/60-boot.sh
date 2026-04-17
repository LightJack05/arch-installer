#!/bin/bash
# stage 60-boot — initramfs hooks, kernel cmdline, UKI build, optional secure boot.
#
# Always:
#   - write HOOKS=(systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)
#   - write /etc/mkinitcpio.d/linux.preset for UKI output
#   - build cmdline with resume=/resume_offset (from /tmp/installer.env)
#   - mkinitcpio -P  →  /efi/EFI/BOOT/BOOTX64.EFI
#
# If SECURE_BOOT=1:
#   - run optional/secure-boot.sh  (creates keys, enrolls)
#   - build UKI via boot_rebuild_uki
#   - sb_sign_all  (sign after build so the signed files are current)
#
# For scheme D: derive UUIDs from the mounted filesystems via findmnt + blkid.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"
# shellcheck source=../lib/bootloader.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/bootloader.sh"

main() {
    cfg_load
    cfg_require INSTALL_MODE RESUME_OFFSET

    boot_write_mkinitcpio_conf
    boot_write_preset

    local cmdline
    case "${INSTALL_MODE}" in
        A)
            local root_uuid
            root_uuid=$(blkid -s UUID -o value "$(findmnt -no SOURCE /)")
            cmdline=$(boot_build_cmdline_scheme_a "${root_uuid}" "${RESUME_OFFSET}")
            ;;
        B)
            cfg_require LUKS_UUID
            cmdline=$(boot_build_cmdline_scheme_b "${LUKS_UUID}" "${RESUME_OFFSET}")
            ;;
        C)
            cfg_require LUKS_UUID
            cmdline=$(boot_build_cmdline_scheme_c "${LUKS_UUID}" "${RESUME_OFFSET}")
            ;;
        D)
            # Detect whether root device is a LUKS mapper or a plain partition.
            local root_source
            root_source=$(findmnt -no SOURCE /)

            if [[ "${root_source}" == /dev/mapper/* ]]; then
                # Encrypted root — find the backing block device UUID.
                local mapper_name="${root_source#/dev/mapper/}"
                local backing_dev
                backing_dev=$(dmsetup deps -o devname "${mapper_name}" \
                    | grep -oP '\(\K[^)]+' | head -n1)
                backing_dev="/dev/${backing_dev}"
                local luks_uuid
                luks_uuid=$(blkid -s UUID -o value "${backing_dev}")

                # Determine whether TPM2 options are in use by checking enrolled keyslots.
                if systemd-cryptenroll --list-devices 2>/dev/null | grep -q "${backing_dev}" \
                    && cryptsetup luksDump "${backing_dev}" 2>/dev/null | grep -q 'tpm2'; then
                    cmdline=$(boot_build_cmdline_scheme_c "${luks_uuid}" "${RESUME_OFFSET}")
                else
                    cmdline=$(boot_build_cmdline_scheme_b "${luks_uuid}" "${RESUME_OFFSET}")
                fi
            else
                # Plain (unencrypted) root.
                local root_uuid
                root_uuid=$(blkid -s UUID -o value "${root_source}")
                cmdline=$(boot_build_cmdline_scheme_a "${root_uuid}" "${RESUME_OFFSET}")
            fi
            ;;
        *)
            die "unknown INSTALL_MODE: ${INSTALL_MODE}"
            ;;
    esac

    boot_write_cmdline "${cmdline}"

    if [[ "${SECURE_BOOT:-0}" == "1" ]]; then
        # Source secureboot lib so sb_sign_all is available in this shell.
        # shellcheck source=../lib/secureboot.sh
        source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/secureboot.sh"

        # Set up keys and enroll BEFORE building the UKI so the sbctl pacman
        # hook (installed by the sbctl package) sees the keys during mkinitcpio.
        "${INSTALLER_ROOT}/optional/secure-boot.sh"

        # Build the UKI.
        boot_rebuild_uki

        # Sign the freshly built UKI images.
        sb_sign_all

        log_info "secure boot: UKI signed"
    else
        boot_rebuild_uki
    fi

}

main "$@"
