#!/bin/bash
# stage 20-disk — partition, (optionally) encrypt, mkfs, mount.
#
# Skipped for scheme D (user already mounted everything at $MANUAL_MOUNT).
# All inputs come from /tmp/installer.env; no prompts here.
#
# Config keys consumed:
#   INSTALL_MODE    — A | B | C | D
#   TARGET_DISK     — e.g. /dev/sda  (schemes A/B/C)
#   FILESYSTEM      — ext4 | btrfs   (schemes A/B/C)
#   LUKS_PASSPHRASE — passphrase for the LUKS container (schemes B/C)
#   TPM_PIN         — PIN for TPM2 enrollment (scheme C only)
#   MANUAL_MOUNT    — mountpoint already prepared by the user (scheme D)
#
# Config keys written:
#   ROOT_DEVICE     — e.g. /dev/sda2 or /dev/mapper/cryptroot
#   LUKS_UUID       — UUID of the raw LUKS partition (schemes B/C)

set -Eeuo pipefail

# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"
# shellcheck source=../lib/disk.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/disk.sh"
# shellcheck source=../lib/encryption.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/encryption.sh"
# shellcheck source=../lib/fs.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/fs.sh"

main() {
    cfg_load
    cfg_require INSTALL_MODE

    case "${INSTALL_MODE}" in
        A|B|C)
            cfg_require TARGET_DISK FILESYSTEM
            ;;
        D)
            cfg_require MANUAL_MOUNT
            log_info "scheme D — user-provided mounts at ${MANUAL_MOUNT}; skipping partitioning"

            # Verify that MANUAL_MOUNT is actually mounted.
            if ! findmnt "${MANUAL_MOUNT}" > /dev/null 2>&1; then
                die "scheme D: '${MANUAL_MOUNT}' is not a mountpoint — mount your filesystems first"
            fi

            # Record what device backs the manual mount (could be a plain partition
            # or /dev/mapper/cryptroot if the user set up LUKS themselves).
            local root_src
            root_src="$(findmnt -no SOURCE "${MANUAL_MOUNT}")"
            cfg_set ROOT_DEVICE "${root_src}"
            log_info "scheme D: ROOT_DEVICE set to ${root_src}"
            return 0
            ;;
        *)
            die "unknown INSTALL_MODE: ${INSTALL_MODE}"
            ;;
    esac

    # -------------------------------------------------------------------------
    # Schemes A, B, C — destructive operations on TARGET_DISK.
    # -------------------------------------------------------------------------

    disk_is_safe "${TARGET_DISK}"
    disk_wipe    "${TARGET_DISK}"

    # Derive partition paths once (used throughout).
    local esp luks root
    esp="$(disk_esp_partition "${TARGET_DISK}")"

    case "${INSTALL_MODE}" in
        # ---------------------------------------------------------------------
        # Scheme A — plain ESP + root (no encryption).
        # ---------------------------------------------------------------------
        A)
            disk_partition_scheme_a "${TARGET_DISK}"
            root="$(disk_data_partition "${TARGET_DISK}")"

            fs_mkfs_esp "${esp}"

            if [[ "${FILESYSTEM}" == "btrfs" ]]; then
                fs_mkfs_root_btrfs "${root}"
                fs_create_btrfs_subvols "${root}"
                fs_mount_btrfs "${root}" /mnt
            else
                fs_mkfs_root_ext4 "${root}"
                fs_mount_ext4 "${root}" /mnt
            fi

            fs_mount_esp "${esp}" /mnt

            cfg_set ROOT_DEVICE "${root}"
            log_info "scheme A complete: ROOT_DEVICE=${root}"
            ;;

        # ---------------------------------------------------------------------
        # Schemes B & C — ESP + LUKS2 root (+ optional TPM2+PIN for C).
        # ---------------------------------------------------------------------
        B|C)
            cfg_require LUKS_PASSPHRASE
            if [[ "${INSTALL_MODE}" == "C" ]]; then
                cfg_require TPM_PIN
            fi

            disk_partition_scheme_bc "${TARGET_DISK}"
            luks="$(disk_data_partition "${TARGET_DISK}")"

            # Format and open the LUKS container.
            enc_format "${luks}" "${LUKS_PASSPHRASE}"
            enc_open   "${luks}" "${LUKS_PASSPHRASE}" cryptroot

            # Scheme C: wipe TPM and enroll passphrase + PIN-protected TPM2 key.
            if [[ "${INSTALL_MODE}" == "C" ]]; then
                enc_tpm_wipe   "${luks}"
                enc_tpm_enroll "${luks}" "${LUKS_PASSPHRASE}" "${TPM_PIN}"
            fi

            # Format the ESP.
            fs_mkfs_esp "${esp}"

            # Format and mount the decrypted root (/dev/mapper/cryptroot).
            if [[ "${FILESYSTEM}" == "btrfs" ]]; then
                fs_mkfs_root_btrfs /dev/mapper/cryptroot
                fs_create_btrfs_subvols /dev/mapper/cryptroot
                fs_mount_btrfs /dev/mapper/cryptroot /mnt
            else
                fs_mkfs_root_ext4 /dev/mapper/cryptroot
                fs_mount_ext4 /dev/mapper/cryptroot /mnt
            fi

            fs_mount_esp "${esp}" /mnt

            # Persist the LUKS UUID (raw partition, not the mapper) and the
            # root device (the mapper) for later stages (60-boot.sh etc.).
            cfg_set LUKS_UUID    "$(enc_get_luks_uuid "${luks}")"
            cfg_set ROOT_DEVICE  /dev/mapper/cryptroot
            log_info "scheme ${INSTALL_MODE} complete: LUKS_UUID=${LUKS_UUID} ROOT_DEVICE=/dev/mapper/cryptroot"
            ;;
    esac
}

main "$@"
