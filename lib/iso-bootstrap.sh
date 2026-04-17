#!/bin/bash
# lib/iso-bootstrap.sh — install all live-ISO dependencies before the TUI starts.
#
# Must be called AFTER 00-precheck (which ensures the pacman keyring is ready).
# The ISO rootfs lives in tmpfs — keep the RAM budget in mind.
#
# Packages installed:
#   Required (warn + continue on failure):
#     sbctl      — secure boot key management (status check in TUI step 19)
#     gh         — GitHub CLI (dotfiles auth in TUI step 18)
#   TUI backend (fallback to whiptail on failure):
#     gum        — primary TUI backend
#   Cosmetic (silently skipped on failure):
#     figlet, lolcat — ASCII splash
#
# Exposes:
#   iso_bootstrap_all  — the single entry point; called by install.sh

set -Eeuo pipefail

# Minimum free RAM (MiB) required before pulling extra packages.
readonly _ISO_RAM_MIN_MIB=512

_iso_free_ram_mib() {
    local kib
    kib=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
    printf '%d' $(( kib / 1024 ))
}

iso_bootstrap_all() {
    local free_mib
    free_mib=$(_iso_free_ram_mib)

    if (( free_mib < _ISO_RAM_MIN_MIB )); then
        log_warn "only ${free_mib} MiB free RAM — skipping extra ISO packages, using whiptail"
        export INSTALLER_TUI=whiptail
        return 0
    fi

    log_info "free RAM: ${free_mib} MiB — syncing pacman database"
    pacman -Sy --noconfirm 2>/dev/null || log_warn "pacman -Sy failed — packages may be stale"

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
    # TUI backend — fall back to whiptail if gum fails
    # ------------------------------------------------------------------
    if pacman -S --noconfirm --needed gum 2>/dev/null; then
        log_info "gum installed"
    else
        log_warn "gum install failed — falling back to whiptail"
        export INSTALLER_TUI=whiptail
    fi

    # ------------------------------------------------------------------
    # Cosmetic extras — silently skipped on failure
    # ------------------------------------------------------------------
    pacman -S --noconfirm --needed figlet lolcat 2>/dev/null \
        && log_info "figlet + lolcat installed" \
        || log_warn "figlet/lolcat install failed — ASCII splash will be skipped"
}
