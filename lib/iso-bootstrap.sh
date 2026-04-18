#!/bin/bash
# lib/iso-bootstrap.sh — install all live-ISO dependencies before the TUI starts.
#
# Must be called AFTER 00-precheck (which ensures the pacman keyring is ready).
# The ISO rootfs lives in tmpfs — keep the RAM budget in mind.
#
# Packages installed:
#   Required (die on failure):
#     gum        — TUI
#   Required (warn + continue on failure):
#     sbctl      — secure boot key management (status check in TUI step 19)
#     gh         — GitHub CLI (dotfiles auth in TUI step 18)
#   Cosmetic (silently skipped on failure):
#     figlet, lolcat — ASCII splash
#
# Exposes:
#   iso_bootstrap_all  — the single entry point; called by install.sh

set -Eeuo pipefail

iso_bootstrap_all() {
    log_info "syncing pacman database"
    pacman -Sy --noconfirm 2>/dev/null || log_warn "pacman -Sy failed — packages may be stale"

    # ------------------------------------------------------------------
    # gum — required TUI; die if unavailable
    # ------------------------------------------------------------------
    pacman -S --noconfirm --needed gum 2>/dev/null \
        || die "gum install failed — cannot start TUI"
    log_info "gum installed"

    # ------------------------------------------------------------------
    # Required live-ISO tools (warn on failure, never die)
    # ------------------------------------------------------------------
    local required_pkgs=(sbctl github-cli)
    local pkg
    for pkg in "${required_pkgs[@]}"; do
        if pacman -S --noconfirm --needed "${pkg}" 2>/dev/null; then
            log_info "${pkg} installed"
        else
            log_warn "${pkg} install failed — some installer features may not work"
        fi
    done

    # ------------------------------------------------------------------
    # Cosmetic extras — silently skipped on failure
    # ------------------------------------------------------------------
    pacman -S --noconfirm --needed figlet lolcat 2>/dev/null \
        && log_info "figlet + lolcat installed" \
        || log_warn "figlet/lolcat install failed — ASCII splash will be skipped"
}
