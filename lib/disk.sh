#!/bin/bash
# lib/disk.sh — disk detection, wipe, and partitioning via sgdisk.
#
# Schemes (see PLAN.md §4):
#   A: p1 ESP 1G (ef00), p2 root rest (8300)
#   B: p1 ESP 1G (ef00), p2 LUKS rest (8309)
#   C: same layout as B (TPM2, no PIN)
#   D: same layout as B (TPM2 + PIN)
#   Z: no-op (user-provided mounts)
#
# Functions:
#   disk_list                  — lsblk output, non-removable first
#   disk_is_safe <dev>         — sanity-check a device looks like a whole disk
#   disk_wipe <dev>            — sgdisk --zap-all + wipefs -a
#   disk_partition_scheme_a <dev>
#   disk_partition_scheme_bc <dev>
#   disk_part <dev> <n>        — compute partition path (handles nvme/mmc p-suffix)
#   disk_esp_partition <dev>   — echo the ESP partition path (e.g. /dev/nvme0n1p1)
#   disk_data_partition <dev>  — echo the data/LUKS partition path (p2)

set -Eeuo pipefail

# Guard against double-sourcing.
if [[ "${__INSTALLER_DISK_SOURCED:-0}" == "1" ]]; then
    return 0
fi
readonly __INSTALLER_DISK_SOURCED=1

# Source common.sh if not already loaded (when disk.sh is used standalone in tests).
_DISK_DIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${__INSTALLER_COMMON_SOURCED:-0}" != "1" ]]; then
    # shellcheck source=common.sh
    source "${_DISK_DIR}/common.sh"
fi

# disk_list — print one line per non-removable whole disk:
#   /dev/sda  500G  Samsung SSD 870
# Non-removable disks (RM=0) are listed first; removable (RM=1) after, dimmed.
disk_list() {
    # lsblk columns: NAME SIZE MODEL TYPE RM
    # Filter TYPE==disk; sort RM=0 first, then RM=1; prefix name with /dev/.
    lsblk -ndo NAME,SIZE,MODEL,TYPE,RM 2>/dev/null \
        | awk '$4=="disk" { print $5, "/dev/"$1, $2, $3 }' \
        | sort -k1,1n \
        | awk '{ $1=""; sub(/^ /,""); print }'
}

# disk_is_safe <dev> — verify the block device is a safe target.
# Dies with a message on any failure.
disk_is_safe() {
    local dev="$1"

    # Strip trailing slash just in case.
    dev="${dev%/}"

    # Must be an absolute path.
    [[ "${dev}" == /dev/* ]] || die "disk_is_safe: '${dev}' is not an absolute /dev/ path"

    local name
    name="$(basename -- "${dev}")"

    # Must exist under /sys/block (i.e. it is a whole disk, not a partition).
    [[ -d "/sys/block/${name}" ]] \
        || die "disk_is_safe: /sys/block/${name} does not exist — '${dev}' is not a whole block device"

    # Must be TYPE=disk according to lsblk.
    local type
    type="$(lsblk -ndo TYPE "${dev}" 2>/dev/null || true)"
    [[ "${type}" == "disk" ]] \
        || die "disk_is_safe: '${dev}' is TYPE '${type}', not 'disk'"

    # Must not be currently mounted (any partition on it).
    if findmnt --source "${dev}" > /dev/null 2>&1; then
        die "disk_is_safe: '${dev}' (or a partition on it) is currently mounted — unmount first"
    fi
    # Also check individual partitions.
    local part
    while IFS= read -r part; do
        if [[ -n "${part}" ]] && findmnt --source "${part}" > /dev/null 2>&1; then
            die "disk_is_safe: partition '${part}' on '${dev}' is currently mounted — unmount first"
        fi
    done < <(lsblk -nlo PATH "${dev}" 2>/dev/null | tail -n +2)

    log_info "disk_is_safe: '${dev}' passed all checks"
}

# disk_wipe <dev> — destroy all partition tables and filesystem signatures.
disk_wipe() {
    local dev="$1"
    run sgdisk --zap-all "${dev}"
    run wipefs -a "${dev}"
    run partprobe "${dev}"
    sleep 1  # let the kernel re-read the partition table
}

# disk_partition_scheme_a <dev> — two partitions: ESP + root.
#   p1: 1 GiB, type ef00 (EFI System), label ESP
#   p2: rest,  type 8300 (Linux filesystem), label ROOT
disk_partition_scheme_a() {
    local dev="$1"
    run sgdisk \
        -n1:0:+1G  -t1:ef00  -c1:ESP \
        -n2:0:0    -t2:8300  -c2:ROOT \
        "${dev}"
    run partprobe "${dev}"
    sleep 1
}

# disk_partition_scheme_bc <dev> — two partitions: ESP + LUKS root.
#   p1: 1 GiB, type ef00 (EFI System), label ESP
#   p2: rest,  type 8309 (Linux LUKS),  label cryptroot
disk_partition_scheme_bc() {
    local dev="$1"
    run sgdisk \
        -n1:0:+1G  -t1:ef00  -c1:ESP \
        -n2:0:0    -t2:8309  -c2:cryptroot \
        "${dev}"
    run partprobe "${dev}"
    sleep 1
}

# disk_part <dev> <n> — return the full partition path for partition number N.
# Handles nvme and mmcblk devices which use a 'p' separator (e.g. nvme0n1p1).
disk_part() {
    local dev="$1" n="$2"
    if [[ "${dev}" =~ (nvme|mmcblk) ]]; then
        printf '%s' "${dev}p${n}"
    else
        printf '%s' "${dev}${n}"
    fi
}

# disk_esp_partition <dev> — partition 1 (ESP).
disk_esp_partition() {
    disk_part "$1" 1
}

# disk_data_partition <dev> — partition 2 (root or LUKS container).
disk_data_partition() {
    disk_part "$1" 2
}
