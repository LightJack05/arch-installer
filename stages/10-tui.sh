#!/bin/bash
# stage 10-tui — single interactive phase. Every subsequent stage reads
# answers from /tmp/installer.env and never prompts.
#
# Screens (see PLAN.md §4 TUI answer set for defaults):
#   1.  splash
#   2.  live keyboard layout (applied immediately via `loadkeys`)
#   3.  install mode A/B/C/D
#   4.  manual mount dir (D only)
#   5.  target disk (A/B/C)
#   6.  filesystem ext4|btrfs (A/B/C)
#   7.  swapfile size (default 1.5×RAM MiB)
#   8.  zram size (default min(RAM/2, 8192) MiB)
#   9.  hostname
#  10.  timezone
#  11.  locale
#  12.  console keymap
#  13.  username
#  14.  user full name (optional)
#  15.  user shell
#  16.  root password (twice, empty allowed → root login disabled)
#  17.  user password (twice, required)
#  18.  LUKS passphrase (twice)                  — B+C
#  19.  TPM2 PIN (twice) + TPM-wipe confirmation — C
#  20.  dotfiles opt-out (default on)
#        └─ if on: run `gh auth login`, capture token → /tmp/installer.ghtoken (0600)
#  21.  secure boot opt-in (warn if not in Setup Mode)
#  22.  surface kernel opt-in
#  23.  additional optional scripts (checklist from optional/)
#  24.  summary recap (go back to any screen)
#  25.  final destructive confirmation (only before scheme A/B/C wipes)
#
# Passwords are hashed via `openssl passwd -6` before cfg_set; plaintext
# never persists. GH token lives in its own 0600 file, not the env file.

set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/config.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/config.sh"
# shellcheck source=../lib/tui.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/tui.sh"

main() {
    cfg_init
    log_info "starting TUI (backend: ${INSTALLER_TUI_BACKEND})"

    # TODO: splash (figlet "Arch Installer" | lolcat; or gum style)

    # TODO: iterate screens. Each screen calls a tui_* wrapper and cfg_set's
    #       the result. Validators live here (hostname regex, timezone existence,
    #       username regex, locale existence, password match, PIN match).

    # TODO: summary recap — render all keys, offer "edit <screen>"
    # TODO: final confirm (only for schemes A/B/C; D skips the wipe)
    :
}

main "$@"
