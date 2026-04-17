#!/bin/bash
# lib/bootloader.sh — mkinitcpio preset, /etc/kernel/cmdline, UKI build.
#
# All paths are chroot-relative (stage 60 runs inside the chroot).
#
# Hook line: systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck
# UKI outputs: /efi/EFI/BOOT/BOOTX64.EFI (default), /efi/EFI/Linux/arch-linux-fallback.efi
#
# Security parameters included in all cmdlines:
#   iommu=force intel_iommu=on amd_iommu=on  — enforce IOMMU on all devices (DMA protection)
#   lockdown=confidentiality                  — block kernel memory reads; implies no hibernation
#
# Functions:
#   boot_write_mkinitcpio_conf
#   boot_write_preset
#   boot_build_cmdline_scheme_a <root_uuid>        — echo cmdline
#   boot_build_cmdline_scheme_b <cryptroot_uuid>
#   boot_build_cmdline_scheme_c <cryptroot_uuid>
#   boot_write_cmdline <cmdline>
#   boot_rebuild_uki                               — mkinitcpio -P

set -Eeuo pipefail

boot_write_mkinitcpio_conf() {
    sed -i 's/^HOOKS=(.*/HOOKS=(systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)/' \
        /etc/mkinitcpio.conf
}

boot_write_preset() {
    mkdir -p /efi/EFI/BOOT /efi/EFI/Linux

    cat > /etc/mkinitcpio.d/linux.preset << 'EOF'
# mkinitcpio preset file for the 'linux' package

ALL_kver="/boot/vmlinuz-linux"
ALL_microcode=(/boot/*-ucode.img)

PRESETS=('default' 'fallback')

default_uki="/efi/EFI/BOOT/BOOTX64.EFI"
default_options="--cmdline /etc/kernel/cmdline"

fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
fallback_options="-S autodetect"
EOF
}

_SECURITY_PARAMS='iommu=force intel_iommu=on amd_iommu=on lockdown=confidentiality'

boot_build_cmdline_scheme_a() {
    local root_uuid="$1"
    printf 'root=UUID=%s rw %s\n' "${root_uuid}" "${_SECURITY_PARAMS}"
}

boot_build_cmdline_scheme_b() {
    local luks_uuid="$1"
    printf 'rd.luks.name=%s=cryptroot root=/dev/mapper/cryptroot rw %s\n' \
        "${luks_uuid}" "${_SECURITY_PARAMS}"
}

boot_build_cmdline_scheme_c() {
    local luks_uuid="$1"
    printf 'rd.luks.name=%s=cryptroot rd.luks.options=%s=tpm2-device=auto root=/dev/mapper/cryptroot rw %s\n' \
        "${luks_uuid}" "${luks_uuid}" "${_SECURITY_PARAMS}"
}

boot_write_cmdline() {
    local cmdline="$1"
    umask 022
    mkdir -p /etc/kernel
    printf '%s\n' "$cmdline" > /etc/kernel/cmdline
}

boot_rebuild_uki() {
    run mkinitcpio -P
}
