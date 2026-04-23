# arch-installer

Opinionated, single-entrypoint Arch Linux installer. TUI up front, unattended everywhere after.

> **Note:** The code in this repository is largely AI-generated (Claude Code / Anthropic). Review carefully before running on real hardware.

## Quickstart

From the Arch ISO:

```sh
pacman -Sy --noconfirm git
git clone https://github.com/LightJack05/arch-installer
cd arch-installer
./install.sh
```

Answer the TUI once. Everything after the final confirmation runs unattended.

## Features

- **Five install modes** chosen in the TUI:
  - **A** — plain: ESP + ext4/btrfs root, no encryption
  - **B** — LUKS2 on root, passphrase only
  - **C** — LUKS2 on root, TPM2 auto-unseal (no PIN, re-enrolled post-reboot to PCR 0+7)
  - **D** — LUKS2 on root, TPM2 + PIN (passphrase as fallback)
  - **Z** — manual: you've already mounted everything, installer runs from there
- **ext4 or btrfs** (btrfs uses `@`, `@home`, `@log`, `@pkg`, `@swap` subvols — no snapper)
- **zRAM + swapfile** for swap (no swap partition, no LVM). Hibernation blocked by lockdown.
- **Direct UKI boot** — no GRUB, no systemd-boot. `/efi/EFI/BOOT/BOOTX64.EFI`.
- **Kernel lockdown** (`lockdown=confidentiality` + IOMMU enforcement) on by default, opt-out in TUI.
- **Secure Boot** via sbctl — opt-in, requires firmware in Setup Mode.
- **Unattended AUR** via yay with a temporary NOPASSWD sudoers dropin (removed at finalize).
- **Dotfiles** opt-out: `gh auth login` runs up front so the first boot is seamless.
- **170+ curated pacman packages** + a small AUR list.
- **Systemd services** enabled at install time (NetworkManager, pipewire, ly, libvirtd, ufw, etc.).

## Layout

```
install.sh        entrypoint — sources libs, dispatches stages in order
lib/              shared helpers (logging, TUI, disk, encryption, fs, swap, bootloader, secureboot)
stages/           numbered stage scripts (00–99), split: ISO-side then chroot-side
  00-precheck     UEFI check, network, NTP, keyring
  10-tui          single interactive phase — all answers saved to /tmp/installer.env
  20-disk         partition, encrypt (LUKS2), format, mount
  25-swap         zRAM config + swapfile creation
  30-pacstrap     base system + microcode + fstab
  40-chroot       hand off to arch-chroot
  50-system       timezone, locale, hostname, sudoers, pacman tweaks
  60-boot         mkinitcpio, UKI preset, kernel cmdline, Secure Boot signing
  70-users        create user, set passwords, temporary NOPASSWD dropin
  80-packages     install packages.txt via pacman
  85-aur          build yay, install aur-packages.txt
  88-optional     run user-selected optional scripts
  90-services     enable services.txt
  95-dotfiles     clone + run dotfiles setup script
  99-finalize     remove NOPASSWD dropin, shred all secrets
config/           packages.txt, aur-packages.txt, services.txt, defaults.env
optional/         opt-in scripts (secure-boot.sh, …)
.claude/agents/   subagents for AI-assisted development
PLAN.md           architecture, design decisions, implementation phases
```

## Configuration

Defaults live in `config/defaults.env`. The TUI overrides all of them interactively. Notable defaults:

| Key | Default |
|-----|---------|
| `TIMEZONE` | `Europe/Berlin` |
| `LOCALE` | `en_US.UTF-8` |
| `USERNAME` | `LightJack05` |
| `SHELL` | `/usr/bin/zsh` |
| `INSTALL_MODE` | `A` |
| `FILESYSTEM` | `ext4` |
| `KERNEL_LOCKDOWN` | `1` (on) |
| `SECURE_BOOT` | `0` (off) |
| `DOTFILES_ENABLED` | `1` (on) |

## License

MIT — see `LICENSE`.
