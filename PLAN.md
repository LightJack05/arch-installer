# Arch Installer Rewrite — Plan

## 1. Current State (Analysis)

### Files
| File | Role | Notes |
|---|---|---|
| `bootstrap.sh` | Runs `pacstrap`, clones setup repo into `/mnt/init/`, arch-chroots | Assumes partitions already mounted at `/mnt`; clones from separate `setup-files` repo |
| `init-system.sh` | Base config, secure boot, mkinitcpio UKI, encryption prompt, orchestrator | Mixes prompts with work; hard-codes `LightJack05`, `Europe/Berlin`, `en_US.UTF-8`, `us` keymap |
| `user.sh` | Creates `LightJack05`, interactive `passwd` | |
| `yay.sh` | Clones + builds `yay` from AUR | Run as user via `sudo -u` from init-system |
| `aur-packages.sh` | Installs AUR pkgs | **Bugs:** runs bare `yay` first; needs sudo password interactively |
| `packages.sh` | `pacman -Syu` from `package-list.txt` | |
| `services.sh` | `systemctl enable …` list | Services hard-coded, drift from package list |
| `dotfiles.sh` | `gh auth login` (interactive mid-install), clones dotfiles, runs setup | Interactive in the middle of the flow |
| `special-stuff/surface-kernel.sh` | Optional Surface kernel | **Bugs:** `grub-mkconfig` under a UKI system; missing `sudo`; `echo << EOF` is malformed |

### Issues
1. **Interactive prompts scattered throughout** — hostname, encryption UUID via `vim`, root passwd, user passwd, `gh auth login`. Cannot run unattended.
2. **No partitioning / encryption setup** — user must hand-craft disks, cryptsetup, LVM before `bootstrap.sh`.
3. **AUR install is not unattended** — `yay` invoked bare; `sudo` prompts interactively; `gh auth login` interactive.
4. **Secure boot always enrolled** — `sbctl enroll-keys -m` always runs.
5. **Fragile encryption UX** — opens `vim` on `ls -lah` output so user copies a UUID into `/etc/kernel/cmdline` by hand.
6. **Separate repo dependency** — `bootstrap.sh` clones `LightJack05/setup-files` instead of self-hosting.
7. **No dry-run, no logging, no resume** — `set -euxo pipefail` dumps raw trace.
8. **`surface-kernel.sh` is broken** — UKI-incompatible and syntactically wrong.
9. **Services list drifts from package list** — hand-maintained.

## 2. Goals (from user request)

1. Unify + clean up scripts, make the process reliable.
2. Move **all** interaction to a single up-front phase; everything after runs unattended.
3. Add basic flare + a TUI at the start.
4. Unattended AUR install (yay + packages, including initial `gh auth login` captured up front).
5. Keep opinionated choices as **defaults** — user can "hit next" to accept, or override in the TUI.
6. Split optional components into opt-in prompts (Secure Boot, Surface kernel, …).
7. Partitioning + full-disk-encryption as **install-time** options (all use zRAM as primary swap and a swapfile on root for secondary swap + hibernation):
   - **A.** Bare: ESP + Root (two partitions)
   - **B.** LUKS on root with passphrase (ESP + one LUKS container → ext4/btrfs at `/`)
   - **C.** LUKS on root with passphrase **and** TPM2+PIN (same layout as B; TPM wiped before enrollment)
   - **D.** Manual: user hands us a directory where `/`, `/efi`, etc. are already mounted, and we skip stage 20 entirely.

## 3. Target Architecture

```
arch-installer/
├── install.sh                     # single entrypoint run from the Arch ISO
├── PLAN.md                        # this file
├── README.md
├── lib/
│   ├── common.sh                  # logging, error trap, confirm(), run(), die()
│   ├── iso-bootstrap.sh           # installs extra UI/tooling deps into ISO ramdisk
│   ├── tui.sh                     # TUI wrappers (gum primary, whiptail fallback)
│   ├── config.sh                  # load/save answers as KEY=value to /tmp/installer.env
│   ├── disk.sh                    # detect disks, wipe, partition (sgdisk)
│   ├── encryption.sh              # LUKS2 format; TPM wipe + systemd-cryptenroll (PIN)
│   ├── fs.sh                      # mkfs (ext4 or btrfs), subvol layout for btrfs, mount
│   ├── swap.sh                    # zram-generator config + swapfile creation + resume_offset calc
│   ├── bootloader.sh              # mkinitcpio preset, UKI path, cmdline builder, resume= wiring
│   └── secureboot.sh              # sbctl create/enroll/sign
├── stages/
│   ├── 00-precheck.sh             # UEFI? net? clock sync? pacman-key populated? RAM free?
│   ├── 10-tui.sh                  # gather ALL answers up front (incl. gh auth if opted in)
│   ├── 20-disk.sh                 # partition + encrypt + mkfs + mount  (skipped in scheme D)
│   ├── 25-swap.sh                 # zram-generator config + swapfile + resume_offset → /tmp/installer.env
│   ├── 30-pacstrap.sh             # base + kernel + ucode + zram-generator + installer-required pkgs
│   ├── 40-chroot.sh               # copies repo into /mnt/root/arch-installer, arch-chroots to 50+
│   ├── 50-system.sh               # timezone, locale, hostname, sudoers, multilib, pacman.conf
│   ├── 60-boot.sh                 # mkinitcpio preset + cmdline (with resume= + resume_offset=) + UKI + (optional) sbctl
│   ├── 70-users.sh                # create user, hashed passwords from stage 10
│   ├── 80-packages.sh             # pacman install from config/packages.txt
│   ├── 85-aur.sh                  # build yay + install AUR unattended (NOPASSWD dropin)
│   ├── 90-services.sh             # enable services from config/services.txt
│   ├── 95-dotfiles.sh             # use captured gh token, clone dotfiles, run setup
│   └── 99-finalize.sh             # remove NOPASSWD dropin, shred secrets, unmount, reboot prompt
├── optional/
│   ├── secure-boot.sh             # opt-in in TUI
│   ├── surface-kernel.sh          # rewritten for UKI
│   └── …
├── config/
│   ├── packages.txt
│   ├── aur-packages.txt
│   ├── services.txt
│   └── defaults.env               # timezone, keymap, locale, user, hostname, fs, swap multiplier, …
└── .claude/
    └── agents/                    # specialized subagents (see section 6)
```

### Flow
```
[ISO boot] → install.sh
  ├─ 00-precheck
  ├─ iso-bootstrap (pacman -Sy gum + small extras)
  ├─ 10-tui  ─ gather answers ─→ /tmp/installer.env   (incl. optional gh token)
  ├─ 20-disk   (destructive — final "are you sure?" before this; skipped for scheme D)
  ├─ 25-swap   (create swapfile on mounted /; record resume_offset)
  ├─ 30-pacstrap
  ├─ 40-chroot → (inside chroot) 50..99 runs unattended
  └─ reboot prompt
```

## 4. Key Technical Decisions

### TUI tool
- **Primary: `gum`** (charmbracelet) — modern look, small (~7 MB), pacman-installed into the ISO at the start of `install.sh`.
- **Fallback: `whiptail`** (from `libnewt`) — present on the Arch ISO by default; used if `gum` install fails or `INSTALLER_TUI=whiptail` is set.
- Small ASCII splash via `figlet` + `lolcat` on entry (cosmetic only; TUI doesn't depend on them).
- **ISO ramdisk budget:** keep extra installs under ~100 MB; `00-precheck` sanity-checks free RAM before pulling extras.

### TUI answer set (all prompted, defaults pre-filled — "hit next" to accept)
| Prompt | Default | Notes |
|---|---|---|
| Keyboard layout (live) | `us` | Applied immediately for the rest of the TUI |
| Install mode | A / B / C / D | D = manual partitions already mounted |
| Target mount point (mode D only) | `/mnt` | text |
| Target disk (modes A/B/C) | first non-removable disk from `lsblk` | Dropdown |
| Filesystem (modes A/B/C) | ext4 | ext4 or btrfs (btrfs: base subvol layout only, no snapper) |
| Swapfile size | `1.5 × RAM` GiB | used for hibernation/resume; lives on root |
| zRAM size | `min(RAM / 2, 8 GiB)` | in-memory compressed swap, higher priority than swapfile |
| Hostname | `archlinux` | text |
| Timezone | `Europe/Berlin` | validated against `/usr/share/zoneinfo` |
| Locale | `en_US.UTF-8` | |
| Console keymap | `us` | |
| Username | `LightJack05` | |
| User full name | *(empty)* | optional |
| User shell | `/usr/bin/zsh` | |
| Root password | prompted twice | empty → root login disabled |
| User password | prompted twice | required |
| LUKS passphrase | prompted twice | modes B + C |
| TPM2 PIN | prompted twice | mode C only |
| Dotfiles (opt-out) | on | if on: `gh auth login` now, captured for stage 95 |
| Secure Boot (opt-in) | off | |
| Surface kernel (opt-in) | off | |
| Extra optional scripts | none | checklist from `optional/` |

All answers written to `/tmp/installer.env`. `gh` token (if captured) in `/tmp/installer.ghtoken` mode `0600`; moved into the chroot at stage 40; used at stage 95; shredded at stage 99.

### Partitioning
- GPT, UEFI only.
- **p1** ESP — 1 GiB, FAT32, mounted at `/efi` (UKI lives directly in the ESP; no separate `/boot`).
- No swap partition in any scheme. Primary swap is zRAM (kernel module, set up by `zram-generator`). Secondary swap / hibernation target is a swapfile on the root filesystem.

### Scheme A — Bare (ESP + Root)
```
p1 ESP    1G     vfat         /efi
p2 root   rest   ext4|btrfs   /
      └─ /swap/swapfile   1.5×RAM   (created post-mkfs, mode 0600, NOCOW on btrfs)
```
- `resume=UUID=<root-fs-uuid> resume_offset=<N>` on cmdline.
- zRAM configured via `/etc/systemd/zram-generator.conf` (activated at first boot).

### Scheme B — LUKS on root (passphrase)
```
p1 ESP                  1G          vfat         /efi
p2 LUKS2 "cryptroot"    rest
   └─ ext4|btrfs on /dev/mapper/cryptroot    /
         └─ /swap/swapfile   1.5×RAM
```
- Single LUKS container → single unlock at boot → single passphrase prompt.
- Resume target is the swapfile inside the decrypted root, so it's available in initramfs right after the LUKS container is opened.
- `cmdline`: `rd.luks.name=<UUID_cryptroot>=cryptroot root=/dev/mapper/cryptroot resume=/dev/mapper/cryptroot resume_offset=<N> rw`

### Scheme C — LUKS on root + passphrase + TPM2-PIN
- Same layout as B — one LUKS container.
- **Passphrase is set first** on the LUKS header (keyslot 0) as the recovery path.
- **TPM is wiped before enrollment**:
  - `systemd-cryptenroll --wipe-slot=tpm2 <luks-part>` (clears any prior TPM keyslot on this header).
  - `tpm2_clear -c p` (platform-auth clear). If that fails, the TUI warns the user to clear the TPM from firmware, then re-runs.
- **Enrollment**: `systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=0+7 <luks-part>`.
- **Both unlock methods stay active**: passphrase (recovery) + TPM2+PIN (daily). PIN is required on every boot.
- `cmdline`: `rd.luks.name=<UUID_cryptroot>=cryptroot rd.luks.options=<UUID_cryptroot>=tpm2-device=auto root=/dev/mapper/cryptroot resume=/dev/mapper/cryptroot resume_offset=<N> rw`
- Pacstrap adds: `tpm2-tools`, `tpm2-tss`.

### Scheme D — Manual partitioning
- User has already done `cryptsetup` / `mkfs` / `mount` in a separate TTY and points the installer at the mount root (default `/mnt`).
- `20-disk.sh` is skipped entirely; `25-swap.sh` still runs (creates the swapfile on whatever is mounted at `/`).
- `60-boot.sh` derives UUIDs / `resume_offset` / cmdline from `findmnt` + `blkid` + the just-created swapfile.
- If a LUKS device is detected under the mount, the TUI asks whether to additionally enroll TPM2+PIN on top of what's already there.

### Filesystem choice
- **ext4** (default).
- **btrfs**: root subvol `@` mounted at `/`, `@home` at `/home`, `@log` at `/var/log`, `@pkg` at `/var/cache/pacman/pkg`, `@swap` at `/swap` (NOCOW, uncompressed; holds the swapfile); mounted with `noatime,compress=zstd,space_cache=v2`; pacstrap adds `btrfs-progs`. No snapper / no snapshot policy — user sets that up themselves.
- Applies only to root; `/efi` is always vfat.

### Swap
- **Primary: zRAM** via `zram-generator` (pacstrapped). Default config in `/etc/systemd/zram-generator.conf`:
  ```
  [zram0]
  zram-size = min(ram / 2, 8192)
  compression-algorithm = zstd
  swap-priority = 100
  ```
- **Secondary: swapfile on root** at `/swap/swapfile` (mode `0600`, size `1.5 × RAM`), lower priority than zRAM so the kernel only spills to disk under real pressure — this is also the hibernation target.
- Creation differs by FS:
  - **ext4:** `fallocate -l <size> /swap/swapfile` → `chmod 600` → `mkswap` → compute `resume_offset` from `filefrag -v /swap/swapfile` (first extent's physical start in FS block units).
  - **btrfs:** dedicated subvol `@swap` mounted at `/swap` (NOCOW, no compression). Use `btrfs filesystem mkswapfile --size <size> /swap/swapfile` (handles NOCOW + preallocation). Compute `resume_offset` via `btrfs inspect-internal map-swapfile -r /swap/swapfile`.
- `/etc/fstab` gets the swapfile with `sw 0 0`. zRAM is not in fstab (generator handles it).

### Initramfs
- `sd-encrypt` systemd hooks: `systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems fsck`. No `lvm2` (no LVM). Resume is handled by systemd via `resume=` + `resume_offset=` on the cmdline — no separate `resume` hook needed.
- UKI output paths: `/efi/EFI/BOOT/BOOTX64.EFI` (default), `/efi/EFI/Linux/arch-linux-fallback.efi`.

### Microcode
- Detect CPU vendor via `/proc/cpuinfo`, pacstrap `amd-ucode` or `intel-ucode`, reference it in the mkinitcpio preset so it's embedded in the UKI.

### Unattended AUR
- After user creation + wheel sudo enabled, drop `/etc/sudoers.d/00-installer`: `<user> ALL=(ALL:ALL) NOPASSWD: ALL`.
- Build `yay` as user: `makepkg -si --noconfirm`.
- Install AUR list: `yay -S --noconfirm --answerclean N --answerdiff N --answeredit N --removemake --cleanafter - < aur-packages.txt`.
- Stage 99 removes `/etc/sudoers.d/00-installer`.

### Dotfiles (opt-out, seamless)
- TUI checkbox defaults **on**.
- If on: run `gh auth login` inside stage 10 while user is at the keyboard. Capture the token via `gh auth token` into `/tmp/installer.ghtoken` (`0600`).
- Stage 40 moves the token into `/mnt/root/.installer-ghtoken`.
- Stage 95 inside chroot:
  - Ensures `gh` + `git` installed.
  - As the user: `gh auth login --with-token < …` + `gh auth setup-git`.
  - `git clone https://github.com/LightJack05/dotfiles --recursive` as the user.
  - Run `setup-complete.sh`.
- Stage 99 shreds both token files.

### Secure Boot (optional)
- If chosen: `sbctl create-keys`, `sbctl enroll-keys -m`, `sbctl sign -s` for UKI + fallback.
- Precondition: firmware in Setup Mode. `00-precheck` surfaces `sbctl status` so the user knows before opting in.

### Logging + reliability
- `set -Eeuo pipefail` (no `-x` by default; gated behind `INSTALLER_DEBUG=1`).
- Shared `log_info/warn/error` with colors; mirror to `/var/log/installer.log` (and `/mnt/var/log/installer.log` after pacstrap).
- `trap` with line number + function name + last command.
- `run()` helper that logs the command before executing — traceability without `set -x` noise.

### Idempotency (best-effort)
- Steps guard with existence checks (`blkid`, `lsblk`, `findmnt`) so reruns after a mid-failure skip finished work where safe.
- Full rerun from scratch is always fine after wiping the target disk.

## 5. Opinionated Defaults (prompted with defaults, "hit next" to accept)
- Timezone `Europe/Berlin`
- Locale `en_US.UTF-8`
- Keymap `us`
- Filesystem `ext4`
- Primary user `LightJack05`, shell `zsh`, wheel + sudo
- Swapfile = `1.5 × RAM`, zRAM = `min(RAM / 2, 8 GiB)`
- Dotfiles on
- Secure Boot off
- Surface kernel off

## 6. Always-On (not prompted)
- UKI direct boot (no systemd-boot / no GRUB)
- `sd-encrypt` hooks
- Multilib enabled
- Service set from `config/services.txt`
- Full package list from `config/packages.txt`
- GPT + UEFI only
- `resume=` always on cmdline

## 7. Subagents (under `.claude/agents/`)

| Agent | Purpose |
|---|---|
| `arch-installer-expert` | Deep Arch install knowledge — LUKS2, `systemd-cryptenroll` (incl. TPM2+PIN and wipe), UKI / mkinitcpio presets, sbctl, pacstrap, chroot flow. Writes robust bash. |
| `tui-ux-designer` | Designs gum + whiptail screens, option layouts, input validation, defaults/"hit next" UX. |
| `bash-reviewer` | Reviews bash for safety (quoting, pipefail, traps), idempotency, portability, shellcheck hygiene. |

## 8. Implementation Phases

1. **Phase 0 — Workspace prep** *(this commit)*: PLAN.md, agents, memory.
2. **Phase 1 — Scaffold** `lib/` + `install.sh` + ISO bootstrap + TUI (gum primary, whiptail fallback, defaults wired in).
3. **Phase 2 — Disk + FS + swap stages** for schemes A / B / C / D × ext4 / btrfs; VM-test each combo. Includes zram-generator config + swapfile + `resume_offset` calc.
4. **Phase 3 — Pacstrap + chroot glue**, rewrite system-config stage.
5. **Phase 4 — Boot stage** (mkinitcpio preset, UKI, cmdline builder w/ `resume=` + `resume_offset=`, optional sbctl).
6. **Phase 5 — Users + packages + AUR (unattended) + services + dotfiles** (with gh token handoff).
7. **Phase 6 — Optional scripts** (secure boot, Surface kernel rewritten for UKI) wired into TUI.
8. **Phase 7 — VM dry-runs** across the matrix.
9. **Phase 8 — README + QUICKSTART**.
