#!/bin/bash
# lib/disk.sh — disk detection, wipe, and partitioning via sgdisk.
#
# Schemes (see PLAN.md §4):
#   A: p1 ESP 1G (ef00), p2 root rest (8300)
#   B: p1 ESP 1G (ef00), p2 LUKS rest (8309)
#   C: same layout as B
#   D: no-op (user-provided mounts)
#
# Functions:
#   disk_list                  — lsblk output, non-removable first
#   disk_is_safe <dev>         — sanity-check a device looks like a whole disk
#   disk_wipe <dev>            — sgdisk --zap-all + wipefs -a
#   disk_partition_scheme_a <dev>
#   disk_partition_scheme_bc <dev>
#   disk_esp_partition <dev>   — echo the ESP partition path (e.g. /dev/nvme0n1p1)
#   disk_data_partition <dev>  — echo the data/LUKS partition path (p2)

set -Eeuo pipefail

disk_list() {
    # TODO: lsblk -ndo NAME,SIZE,MODEL,TYPE,RM  → filter TYPE=disk, sort RM=0 first
    :
}

disk_is_safe() {
    local dev="$1"
    # TODO: verify /sys/block/<name> exists, TYPE=disk, not currently mounted.
    :
}

disk_wipe() {
    local dev="$1"
    # TODO: sgdisk --zap-all "$dev"; wipefs -a "$dev"; partprobe "$dev"
    :
}

disk_partition_scheme_a() {
    local dev="$1"
    # p1 ESP 1GiB ef00
    # p2 root rest 8300
    # TODO: sgdisk -n1:0:+1G -t1:ef00 -c1:ESP \
    #              -n2:0:0     -t2:8300 -c2:ROOT "$dev"
    # TODO: partprobe "$dev"
    :
}

disk_partition_scheme_bc() {
    local dev="$1"
    # p1 ESP 1GiB ef00
    # p2 LUKS rest 8309
    # TODO: sgdisk -n1:0:+1G -t1:ef00 -c1:ESP \
    #              -n2:0:0     -t2:8309 -c2:cryptroot "$dev"
    # TODO: partprobe "$dev"
    :
}

disk_esp_partition() {
    local dev="$1"
    # TODO: echo "${dev}1" — but handle nvme/mmc "p" suffix correctly.
    :
}

disk_data_partition() {
    local dev="$1"
    # TODO: echo "${dev}2" — same suffix caveat.
    :
}
