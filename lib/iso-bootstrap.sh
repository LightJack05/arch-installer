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

# Minimum free RAM (in MiB) required before pulling extra packages.
readonly _ISO_RAM_MIN_MIB=512

# --- Internal helper ----------------------------------------------------------
_iso_free_ram_mib() {
    # Read MemAvailable from /proc/meminfo, convert kB → MiB.
    local kib
    kib=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
    printf '%d' $(( kib / 1024 ))
}

# --- Public functions ---------------------------------------------------------

iso_ensure_gum() {
    # Try to install gum from pacman. On failure, export INSTALLER_TUI=whiptail
    # so tui.sh falls back gracefully. Never calls die().
    if pacman -Sy --noconfirm --needed gum 2>/dev/null; then
        log_info "gum installed successfully"
    else
        log_warn "gum install failed (no network or mirror issue) — falling back to whiptail"
        export INSTALLER_TUI=whiptail
    fi
}

iso_ensure_flare() {
    # Try to install figlet and lolcat (cosmetic splash only).
    # Failure is silently ignored beyond a warning.
    if ! pacman -Sy --noconfirm --needed figlet lolcat 2>/dev/null; then
        log_warn "figlet/lolcat install failed — ASCII splash will be skipped"
    else
        log_info "figlet + lolcat installed successfully"
    fi
}

iso_bootstrap_all() {
    # Check available RAM before pulling anything.
    local free_mib
    free_mib=$(_iso_free_ram_mib)

    if (( free_mib < _ISO_RAM_MIN_MIB )); then
        log_warn "only ${free_mib} MiB free RAM (need ${_ISO_RAM_MIN_MIB} MiB) — skipping extra ISO packages, using whiptail"
        export INSTALLER_TUI=whiptail
        return 0
    fi

    log_info "free RAM: ${free_mib} MiB — proceeding with ISO package installation"
    iso_ensure_gum
    iso_ensure_flare
}
