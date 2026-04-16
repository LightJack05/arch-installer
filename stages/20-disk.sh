#!/bin/bash
# stage 20-disk — partition, (optionally) encrypt, mkfs, mount.
#
# Skipped for scheme D (user already mounted everything at $MANUAL_MOUNT).
# All inputs come from /tmp/installer.env; no prompts here.

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
            return 0
            ;;
        *)
            die "unknown INSTALL_MODE: ${INSTALL_MODE}"
            ;;
    esac

    # TODO: disk_is_safe "$TARGET_DISK" || die
    # TODO: disk_wipe "$TARGET_DISK"

    case "${INSTALL_MODE}" in
        A)
            # TODO: disk_partition_scheme_a "$TARGET_DISK"
            # TODO: esp=$(disk_esp_partition "$TARGET_DISK"); root=$(disk_data_partition "$TARGET_DISK")
            # TODO: fs_mkfs_esp "$esp"
            # TODO: if [[ "$FILESYSTEM" == btrfs ]]; then
            #         fs_mkfs_root_btrfs "$root"
            #         fs_create_btrfs_subvols "$root"
            #       else
            #         fs_mkfs_root_ext4 "$root"
            #       fi
            # TODO: fs_mount_scheme_a "$root" "$esp"
            :
            ;;
        B|C)
            # TODO: disk_partition_scheme_bc "$TARGET_DISK"
            # TODO: esp=$(disk_esp_partition "$TARGET_DISK"); luks=$(disk_data_partition "$TARGET_DISK")
            # TODO: enc_format "$luks" "$LUKS_PASSPHRASE"
            # TODO: enc_open   "$luks" "$LUKS_PASSPHRASE" cryptroot
            # TODO: if [[ "$INSTALL_MODE" == C ]]; then
            #         enc_tpm_wipe   "$luks"
            #         enc_tpm_enroll "$luks" "$TPM_PIN"
            #       fi
            # TODO: fs_mkfs_esp "$esp"
            # TODO: mkfs on /dev/mapper/cryptroot (ext4 or btrfs + subvols)
            # TODO: fs_mount_scheme_bc /dev/mapper/cryptroot "$esp"
            # TODO: cfg_set LUKS_UUID "$(enc_get_luks_uuid "$luks")"
            :
            ;;
    esac
}

main "$@"
