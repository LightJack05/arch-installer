#!/bin/bash
# lib/bootloader.sh — mkinitcpio preset, /etc/kernel/cmdline, UKI build.
#
# All paths are chroot-relative (stage 60 runs inside the chroot).
#
# Hook line: systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck
# UKI outputs: /efi/EFI/BOOT/BOOTX64.EFI (default), /efi/EFI/Linux/arch-linux-fallback.efi
#
# Security parameters (included when KERNEL_LOCKDOWN=1, which is the default):
#   iommu=force intel_iommu=on amd_iommu=on  — enforce IOMMU on all devices (DMA protection)
#   lockdown=confidentiality                  — block kernel memory reads; implies no hibernation
#
# Functions:
#   boot_write_mkinitcpio_conf
#   boot_write_preset
#   boot_build_cmdline_plain <root_uuid>           — echo cmdline (mode A)
#   boot_build_cmdline_luks <cryptroot_uuid>       — mode B (passphrase only)
#   boot_build_cmdline_luks_tpm2 <cryptroot_uuid>  — modes C+D (TPM2 auto-unseal)
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

boot_build_cmdline_plain() {
    local root_uuid="$1"
    printf 'root=UUID=%s rw %s\n' "${root_uuid}" "${_SECURITY_PARAMS}"
}

boot_build_cmdline_luks() {
    local luks_uuid="$1"
    printf 'rd.luks.name=%s=cryptroot root=/dev/mapper/cryptroot rw %s\n' \
        "${luks_uuid}" "${_SECURITY_PARAMS}"
}

boot_build_cmdline_luks_tpm2() {
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
