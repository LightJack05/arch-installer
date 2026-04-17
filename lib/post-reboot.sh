#!/bin/bash
# lib/post-reboot.sh — generic one-shot first-boot runner for installer tasks.
#
# Any stage that needs to run something after the first reboot should:
#   1. source this file
#   2. call post_reboot_ensure_framework   (idempotent)
#   3. write a numbered *.sh script into "${POST_REBOOT_DIR}"
#
# On first boot installer-post-reboot.service runs every *.sh in POST_REBOOT_DIR
# in sorted order, then removes the entire framework — scripts directory, runner
# binary, and unit file — so nothing is left on subsequent boots.
# ConditionPathExists provides an extra safety net if the unit file outlives the
# directory for any reason.
#
# Exported variable (available after sourcing):
#   POST_REBOOT_DIR   — directory to drop scripts into

set -Eeuo pipefail

if [[ "${__INSTALLER_POST_REBOOT_SOURCED:-0}" == "1" ]]; then
    return 0
fi
readonly __INSTALLER_POST_REBOOT_SOURCED=1

_PR_LIBDIR="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${__INSTALLER_COMMON_SOURCED:-0}" != "1" ]]; then
    # shellcheck source=common.sh
    source "${_PR_LIBDIR}/common.sh"
fi

readonly POST_REBOOT_DIR="/etc/installer-post-reboot.d"
readonly _POST_REBOOT_BIN="/usr/local/bin/installer-post-reboot"
readonly _POST_REBOOT_UNIT="/etc/systemd/system/installer-post-reboot.service"
readonly _POST_REBOOT_SVC="installer-post-reboot.service"

# post_reboot_ensure_framework
# Idempotently install the runner binary, systemd unit, and scripts directory.
# Safe to call from multiple stages — only installs once.
post_reboot_ensure_framework() {
    [[ -f "${_POST_REBOOT_BIN}" ]] && return 0

    install -d -m 755 "${POST_REBOOT_DIR}"

    cat > "${_POST_REBOOT_BIN}" << '_RUNNER_EOF_'
#!/bin/bash
set -euo pipefail
DIR=/etc/installer-post-reboot.d
BIN=/usr/local/bin/installer-post-reboot
UNIT=/etc/systemd/system/installer-post-reboot.service
SVC=installer-post-reboot.service

# Remove the binary on exit — safe because the kernel already has the file
# mapped; the inode is freed once this process exits.
trap 'rm -f "${BIN}"' EXIT

shopt -s nullglob
scripts=( "${DIR}"/*.sh )

if (( ${#scripts[@]} == 0 )); then
    echo "post-reboot: no scripts found, nothing to do"
else
    for script in "${scripts[@]}"; do
        echo "post-reboot: running ${script}"
        bash "${script}" || echo "post-reboot: ${script} exited with $? (continuing)"
    done
fi

# Self-cleanup. Skipping daemon-reload to avoid disturbing the running unit;
# systemd will notice the missing unit file on the next boot's implicit reload.
systemctl disable "${SVC}" 2>/dev/null || true
rm -f "${UNIT}"
rm -rf "${DIR}"
_RUNNER_EOF_
    chmod 755 "${_POST_REBOOT_BIN}"

    cat > "${_POST_REBOOT_UNIT}" << '_UNIT_EOF_'
[Unit]
Description=Installer post-reboot tasks (first-boot only)
ConditionPathExists=/etc/installer-post-reboot.d
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/installer-post-reboot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
_UNIT_EOF_

    run systemctl enable "${_POST_REBOOT_SVC}"
    log_info "post-reboot framework installed"
}
