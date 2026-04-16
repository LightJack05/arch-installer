#!/bin/bash
# lib/iso-bootstrap.sh — install extra TUI tooling into the Arch ISO ramdisk.
#
# Keep the RAM budget in mind: the ISO rootfs is in tmpfs. 00-precheck checks
# free RAM before this is called. If network is missing, fall back to whiptail
# (always present on the ISO) — do not abort.
#
# Exposes:
#   iso_ensure_gum         — pacman -Sy gum (best-effort)
#   iso_ensure_flare       — pacman -Sy figlet lolcat (cosmetic, best-effort)
#   iso_bootstrap_all      — called by install.sh before stage 00 output

set -Eeuo pipefail

# TODO: implementations — keep installs best-effort; set a flag for tui.sh so
# it knows which backend to use. Do not use `die` on failure here.

iso_ensure_gum() {
    # TODO: pacman -Sy --noconfirm --needed gum || log_warn "gum unavailable, falling back to whiptail"
    :
}

iso_ensure_flare() {
    # TODO: pacman -Sy --noconfirm --needed figlet lolcat || true
    :
}

iso_bootstrap_all() {
    iso_ensure_gum
    iso_ensure_flare
}
