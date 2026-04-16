#!/bin/bash
# lib/bootloader.sh — mkinitcpio preset, /etc/kernel/cmdline, UKI build.
#
# All paths are chroot-relative (stage 60 runs inside the chroot).
#
# Hook line: systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck
# UKI outputs: /efi/EFI/BOOT/BOOTX64.EFI (default), /efi/EFI/Linux/arch-linux-fallback.efi
#
# Functions:
#   boot_write_mkinitcpio_conf
#   boot_write_preset
#   boot_build_cmdline_scheme_a <root_uuid> <resume_offset>   — echo cmdline
#   boot_build_cmdline_scheme_b <cryptroot_uuid> <resume_offset>
#   boot_build_cmdline_scheme_c <cryptroot_uuid> <resume_offset>
#   boot_write_cmdline <cmdline>
#   boot_rebuild_uki                                          — mkinitcpio -P

set -Eeuo pipefail

boot_write_mkinitcpio_conf() {
    # TODO: sed -i to replace HOOKS=(...) in /etc/mkinitcpio.conf with:
    #   HOOKS=(systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)
    :
}

boot_write_preset() {
    # TODO: write /etc/mkinitcpio.d/linux.preset:
    #   ALL_kver="/boot/vmlinuz-linux"
    #   ALL_microcode=(/boot/*-ucode.img)
    #   PRESETS=('default' 'fallback')
    #   default_uki="/efi/EFI/BOOT/BOOTX64.EFI"
    #   default_options="--cmdline /etc/kernel/cmdline"
    #   fallback_uki="/efi/EFI/Linux/arch-linux-fallback.efi"
    #   fallback_options="-S autodetect"
    # Also: mkdir -p /efi/EFI/BOOT /efi/EFI/Linux
    :
}

boot_build_cmdline_scheme_a() {
    local root_uuid="$1" resume_offset="$2"
    printf 'root=UUID=%s resume=UUID=%s resume_offset=%s rw\n' \
        "${root_uuid}" "${root_uuid}" "${resume_offset}"
}

boot_build_cmdline_scheme_b() {
    local luks_uuid="$1" resume_offset="$2"
    printf 'rd.luks.name=%s=cryptroot root=/dev/mapper/cryptroot resume=/dev/mapper/cryptroot resume_offset=%s rw\n' \
        "${luks_uuid}" "${resume_offset}"
}

boot_build_cmdline_scheme_c() {
    local luks_uuid="$1" resume_offset="$2"
    printf 'rd.luks.name=%s=cryptroot rd.luks.options=%s=tpm2-device=auto root=/dev/mapper/cryptroot resume=/dev/mapper/cryptroot resume_offset=%s rw\n' \
        "${luks_uuid}" "${luks_uuid}" "${resume_offset}"
}

boot_write_cmdline() {
    local cmdline="$1"
    # TODO: umask 022; printf '%s\n' "$cmdline" > /etc/kernel/cmdline
    :
}

boot_rebuild_uki() {
    # TODO: mkinitcpio -P
    :
}
