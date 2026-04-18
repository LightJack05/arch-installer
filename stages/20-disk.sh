#!/bin/bash
# stage 20-disk — partition, (optionally) encrypt, mkfs, mount.
#
# Skipped for scheme Z (user already mounted everything at $MANUAL_MOUNT).
# All inputs come from /tmp/installer.env; no prompts here.
#
# Config keys consumed:
#   INSTALL_MODE    — A | B | C | D | Z
#   TARGET_DISK     — e.g. /dev/sda  (schemes A/B/C/D)
#   FILESYSTEM      — ext4 | btrfs   (schemes A/B/C/D)
#   LUKS_PASSPHRASE — passphrase for the LUKS container (schemes B/C/D)
#   TPM_PIN         — PIN for TPM2 enrollment (scheme D only)
#   MANUAL_MOUNT    — mountpoint already prepared by the user (scheme Z)
#
# Config keys written:
#   ROOT_DEVICE     — e.g. /dev/sda2 or /dev/mapper/cryptroot
#   LUKS_UUID       — UUID of the raw LUKS partition (schemes B/C/D)

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
        A|B|C|D)
            cfg_require TARGET_DISK FILESYSTEM
            ;;
        Z)
            cfg_require MANUAL_MOUNT
            log_info "scheme Z — user-provided mounts at ${MANUAL_MOUNT}; skipping partitioning"

            # Verify that MANUAL_MOUNT is actually mounted.
            if ! findmnt "${MANUAL_MOUNT}" > /dev/null 2>&1; then
                die "scheme Z: '${MANUAL_MOUNT}' is not a mountpoint — mount your filesystems first"
            fi

            # Record what device backs the manual mount (could be a plain partition
            # or /dev/mapper/cryptroot if the user set up LUKS themselves).
            local root_src
            root_src="$(findmnt -no SOURCE "${MANUAL_MOUNT}")"
            cfg_set ROOT_DEVICE "${root_src}"
            log_info "scheme Z: ROOT_DEVICE set to ${root_src}"
            return 0
            ;;
        *)
            die "unknown INSTALL_MODE: ${INSTALL_MODE}"
            ;;
    esac

    # -------------------------------------------------------------------------
    # Schemes A, B, C, D — destructive operations on TARGET_DISK.
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
        # Scheme B — ESP + LUKS2 root (passphrase only).
        # ---------------------------------------------------------------------
        B)
            cfg_require LUKS_PASSPHRASE

            disk_partition_scheme_bc "${TARGET_DISK}"
            luks="$(disk_data_partition "${TARGET_DISK}")"

            enc_format "${luks}" "${LUKS_PASSPHRASE}"
            enc_open   "${luks}" "${LUKS_PASSPHRASE}" cryptroot

            fs_mkfs_esp "${esp}"

            if [[ "${FILESYSTEM}" == "btrfs" ]]; then
                fs_mkfs_root_btrfs /dev/mapper/cryptroot
                fs_create_btrfs_subvols /dev/mapper/cryptroot
                fs_mount_btrfs /dev/mapper/cryptroot /mnt
            else
                fs_mkfs_root_ext4 /dev/mapper/cryptroot
                fs_mount_ext4 /dev/mapper/cryptroot /mnt
            fi

            fs_mount_esp "${esp}" /mnt

            cfg_set LUKS_UUID    "$(enc_get_luks_uuid "${luks}")"
            cfg_set ROOT_DEVICE  /dev/mapper/cryptroot
            log_info "scheme B complete: LUKS_UUID=${LUKS_UUID} ROOT_DEVICE=/dev/mapper/cryptroot"
            ;;

        # ---------------------------------------------------------------------
        # Scheme C — ESP + LUKS2 root + TPM2 (automatic unsealing, no PIN).
        # ---------------------------------------------------------------------
        C)
            cfg_require LUKS_PASSPHRASE

            disk_partition_scheme_bc "${TARGET_DISK}"
            luks="$(disk_data_partition "${TARGET_DISK}")"

            enc_format "${luks}" "${LUKS_PASSPHRASE}"
            enc_open   "${luks}" "${LUKS_PASSPHRASE}" cryptroot

            enc_tpm_wipe         "${luks}"
            enc_tpm_enroll_nopin "${luks}" "${LUKS_PASSPHRASE}"

            fs_mkfs_esp "${esp}"

            if [[ "${FILESYSTEM}" == "btrfs" ]]; then
                fs_mkfs_root_btrfs /dev/mapper/cryptroot
                fs_create_btrfs_subvols /dev/mapper/cryptroot
                fs_mount_btrfs /dev/mapper/cryptroot /mnt
            else
                fs_mkfs_root_ext4 /dev/mapper/cryptroot
                fs_mount_ext4 /dev/mapper/cryptroot /mnt
            fi

            fs_mount_esp "${esp}" /mnt

            cfg_set LUKS_UUID    "$(enc_get_luks_uuid "${luks}")"
            cfg_set ROOT_DEVICE  /dev/mapper/cryptroot
            log_info "scheme C complete: LUKS_UUID=${LUKS_UUID} ROOT_DEVICE=/dev/mapper/cryptroot"
            ;;

        # ---------------------------------------------------------------------
        # Scheme D — ESP + LUKS2 root + TPM2 + PIN.
        # ---------------------------------------------------------------------
        D)
            cfg_require LUKS_PASSPHRASE TPM_PIN

            disk_partition_scheme_bc "${TARGET_DISK}"
            luks="$(disk_data_partition "${TARGET_DISK}")"

            enc_format "${luks}" "${LUKS_PASSPHRASE}"
            enc_open   "${luks}" "${LUKS_PASSPHRASE}" cryptroot

            enc_tpm_wipe   "${luks}"
            enc_tpm_enroll "${luks}" "${LUKS_PASSPHRASE}" "${TPM_PIN}"

            fs_mkfs_esp "${esp}"

            if [[ "${FILESYSTEM}" == "btrfs" ]]; then
                fs_mkfs_root_btrfs /dev/mapper/cryptroot
                fs_create_btrfs_subvols /dev/mapper/cryptroot
                fs_mount_btrfs /dev/mapper/cryptroot /mnt
            else
                fs_mkfs_root_ext4 /dev/mapper/cryptroot
                fs_mount_ext4 /dev/mapper/cryptroot /mnt
            fi

            fs_mount_esp "${esp}" /mnt

            cfg_set LUKS_UUID    "$(enc_get_luks_uuid "${luks}")"
            cfg_set ROOT_DEVICE  /dev/mapper/cryptroot
            log_info "scheme D complete: LUKS_UUID=${LUKS_UUID} ROOT_DEVICE=/dev/mapper/cryptroot"
            ;;
    esac
}

main "$@"
