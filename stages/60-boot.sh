#!/bin/bash
# stage 60-boot — initramfs hooks, kernel cmdline, UKI build, optional secure boot.
#
# Always:
#   - write HOOKS=(systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)
#   - write /etc/mkinitcpio.d/linux.preset for UKI output
#   - build cmdline (+ security params if KERNEL_LOCKDOWN=1, default on)
#   - mkinitcpio -P  →  /efi/EFI/BOOT/BOOTX64.EFI
#
# If SECURE_BOOT=1:
#   - run optional/secure-boot.sh  (creates keys, enrolls)
#   - build UKI via boot_rebuild_uki
#   - sb_sign_all  (sign after build so the signed files are current)
#
# For scheme C (TPM2+PIN):
#   - stage 20 enrolled TPM2 with PCR 0 only so the first boot works regardless
#     of Secure Boot state changes during installation.
#   - This stage queues a post-reboot task (via lib/post-reboot.sh) that
#     re-enrolls TPM2 with PCR 0+7 on first boot, once the system has booted
#     with its final Secure Boot state.  Credentials are stored root-only on
#     the encrypted partition and shredded immediately after re-enrollment.
#
# For scheme E (TPM2, no PIN):
#   - identical cmdline to C (rd.luks.options=tpm2-device=auto).
#   - queues a post-reboot re-enrollment with PCR 0+7, no PIN.
#
# For scheme D: derive UUIDs from the mounted filesystems via findmnt + blkid.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"
# shellcheck source=../lib/bootloader.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/bootloader.sh"
# shellcheck source=../lib/post-reboot.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/post-reboot.sh"

main() {
    cfg_load
    cfg_require INSTALL_MODE

    # Clear security params if the user opted out of kernel lockdown.
    if [[ "${KERNEL_LOCKDOWN:-1}" != "1" ]]; then
        _SECURITY_PARAMS=''
        log_info "kernel lockdown disabled — security params omitted from cmdline"
    fi

    boot_write_mkinitcpio_conf
    boot_write_preset

    local cmdline
    case "${INSTALL_MODE}" in
        A)
            local root_uuid
            root_uuid=$(blkid -s UUID -o value "$(findmnt -no SOURCE /)")
            cmdline=$(boot_build_cmdline_scheme_a "${root_uuid}")
            ;;
        B)
            cfg_require LUKS_UUID
            cmdline=$(boot_build_cmdline_scheme_b "${LUKS_UUID}")
            ;;
        C)
            cfg_require LUKS_UUID
            cmdline=$(boot_build_cmdline_scheme_c "${LUKS_UUID}")
            ;;
        E)
            cfg_require LUKS_UUID
            cmdline=$(boot_build_cmdline_scheme_c "${LUKS_UUID}")
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
                    cmdline=$(boot_build_cmdline_scheme_c "${luks_uuid}")
                else
                    cmdline=$(boot_build_cmdline_scheme_b "${luks_uuid}")
                fi
            else
                # Plain (unencrypted) root.
                local root_uuid
                root_uuid=$(blkid -s UUID -o value "${root_source}")
                cmdline=$(boot_build_cmdline_scheme_a "${root_uuid}")
            fi
            ;;
        *)
            die "unknown INSTALL_MODE: ${INSTALL_MODE}"
            ;;
    esac

    # btrfs roots need rootflags=subvol=@ so the kernel mounts the right subvol.
    local fstype
    fstype=$(findmnt -no FSTYPE /)
    if [[ "${fstype}" == "btrfs" ]]; then
        cmdline="${cmdline%$'\n'} rootflags=subvol=@"
    fi

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

    # Scheme C: queue a first-boot re-enrollment of TPM2 with PCR 0+7.
    # Stage 20 used PCR 0 only because PCR 7 (Secure Boot state) is a boot-time
    # measurement — it cannot reflect key changes made during this session.
    if [[ "${INSTALL_MODE}" == "C" ]]; then
        cfg_require LUKS_UUID LUKS_PASSPHRASE TPM_PIN

        post_reboot_ensure_framework

        # Store credentials root-only on the encrypted partition.
        local creds_dir="/root/.tpm2-reenroll"
        install -d -m 700 "${creds_dir}"
        printf '%s' "${LUKS_UUID}"       > "${creds_dir}/uuid"
        printf '%s' "${LUKS_PASSPHRASE}" > "${creds_dir}/passphrase"
        printf '%s' "${TPM_PIN}"         > "${creds_dir}/pin"
        chmod 600 "${creds_dir}/passphrase" "${creds_dir}/pin"

        cat > "${POST_REBOOT_DIR}/10-tpm2-reenroll.sh" << '_ENROLL_EOF_'
#!/bin/bash
set -euo pipefail
CREDS=/root/.tpm2-reenroll
[[ -d "${CREDS}" ]] || exit 0
UUID=$(cat "${CREDS}/uuid")
DEV=$(blkid -l -t UUID="${UUID}" -o device)
[[ -n "${DEV}" ]] || { echo "tpm2-reenroll: UUID ${UUID} not found" >&2; exit 1; }
# Shred credentials on exit regardless of success or failure.
trap 'unset PIN; find "${CREDS}" -type f -exec shred -u {} \; 2>/dev/null; rm -rf "${CREDS}"' EXIT
# Export NEWPIN so the enrollment call reads the PIN non-interactively.
# systemd-cryptenroll reads $NEWPIN (not $PIN) when setting a new TPM2 PIN.
export NEWPIN
NEWPIN=$(cat "${CREDS}/pin")
# Wipe the bootstrap PCR-0-only slot enrolled during installation.
systemd-cryptenroll --wipe-slot=tpm2 \
    --unlock-key-file="${CREDS}/passphrase" "${DEV}" || true
# Enroll with PCR 0+7: firmware code + Secure Boot state.
systemd-cryptenroll \
    --tpm2-device=auto \
    --tpm2-with-pin=yes \
    --tpm2-pcrs=0+7 \
    --unlock-key-file="${CREDS}/passphrase" \
    "${DEV}"
echo "tpm2-reenroll: TPM2 re-enrolled with PCR 0+7 binding"
_ENROLL_EOF_
        chmod 755 "${POST_REBOOT_DIR}/10-tpm2-reenroll.sh"
        log_info "TPM2 re-enrollment queued for first boot (will bind PCR 0+7)"
    fi

    # Scheme E: queue a first-boot re-enrollment of TPM2 with PCR 0+7 (no PIN).
    if [[ "${INSTALL_MODE}" == "E" ]]; then
        cfg_require LUKS_UUID LUKS_PASSPHRASE

        post_reboot_ensure_framework

        local creds_dir="/root/.tpm2-reenroll"
        install -d -m 700 "${creds_dir}"
        printf '%s' "${LUKS_UUID}"       > "${creds_dir}/uuid"
        printf '%s' "${LUKS_PASSPHRASE}" > "${creds_dir}/passphrase"
        chmod 600 "${creds_dir}/passphrase"

        cat > "${POST_REBOOT_DIR}/10-tpm2-reenroll.sh" << '_ENROLL_EOF_'
#!/bin/bash
set -euo pipefail
CREDS=/root/.tpm2-reenroll
[[ -d "${CREDS}" ]] || exit 0
UUID=$(cat "${CREDS}/uuid")
DEV=$(blkid -l -t UUID="${UUID}" -o device)
[[ -n "${DEV}" ]] || { echo "tpm2-reenroll: UUID ${UUID} not found" >&2; exit 1; }
trap 'find "${CREDS}" -type f -exec shred -u {} \; 2>/dev/null; rm -rf "${CREDS}"' EXIT
systemd-cryptenroll --wipe-slot=tpm2 \
    --unlock-key-file="${CREDS}/passphrase" "${DEV}" || true
systemd-cryptenroll \
    --tpm2-device=auto \
    --tpm2-with-pin=no \
    --tpm2-pcrs=0+7 \
    --unlock-key-file="${CREDS}/passphrase" \
    "${DEV}"
echo "tpm2-reenroll: TPM2 re-enrolled with PCR 0+7 binding (no PIN)"
_ENROLL_EOF_
        chmod 755 "${POST_REBOOT_DIR}/10-tpm2-reenroll.sh"
        log_info "TPM2 re-enrollment queued for first boot (will bind PCR 0+7, no PIN)"
    fi

}

main "$@"
