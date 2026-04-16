# arch-installer

Opinionated, single-entrypoint Arch Linux installer. TUI up front, unattended everywhere after.

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

- **Four install modes** chosen in the TUI:
  - **A** — bare: ESP + root
  - **B** — LUKS on root with passphrase
  - **C** — LUKS on root with passphrase + TPM2-PIN (TPM wiped and re-enrolled)
  - **D** — manual: you've already mounted everything, we run from there
- **ext4 or btrfs** (btrfs uses `@`, `@home`, `@log`, `@pkg`, `@swap` subvols — no snapper)
- **zRAM + swapfile** for swap (no swap partition, no LVM). Hibernation/resume via the swapfile.
- **Direct UKI boot** — no GRUB, no systemd-boot. `/efi/EFI/BOOT/BOOTX64.EFI`.
- **Unattended AUR** via yay + a temporary NOPASSWD sudoers dropin (removed at the end).
- **Dotfiles**, opt-out: `gh auth login` happens up front so the first boot is seamless.
- **Optional at install time**: Secure Boot (sbctl), Surface kernel.

## Layout

```
install.sh        entrypoint — dispatches stages
lib/              shared helpers (logging, TUI, disk, encryption, fs, swap, bootloader, sb)
stages/           numbered stages, run in order
optional/         opt-in scripts invoked when enabled in the TUI
config/           packages, AUR list, services, defaults.env
.claude/agents/   subagents (arch-installer-expert, tui-ux-designer, bash-reviewer)
PLAN.md           full architecture + design decisions
```

See `PLAN.md` for the full design.

## Status

Scaffolded. Stage bodies are TODOs. See `PLAN.md` §8 for implementation phases.

## License

MIT — see `LICENSE`.
