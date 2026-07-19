#!/bin/bash
# Restore the stock Ubuntu i915 module for one (or every) installed kernel ABI.
#
# Usage:
#   sudo ./restore-original-i915.sh                # restores ALL ABIs that have a *.orig backup
#   sudo ./restore-original-i915.sh 6.17.0-23-generic   # restores one specific ABI
#
# A reboot is required for the change to take effect.
set -euo pipefail

restore_one() {
    local abi="$1"
    local dest="/lib/modules/${abi}/kernel/drivers/gpu/drm/i915/i915.ko.zst"
    if [ ! -f "${dest}.orig" ]; then
        echo "[skip] ${abi}: no backup at ${dest}.orig"
        return 0
    fi
    cp -av "${dest}.orig" "${dest}"
    depmod -a "${abi}"
    echo "[ok]   ${abi}: stock module restored"
}

if [ $# -ge 1 ]; then
    restore_one "$1"
else
    found=0
    for d in /lib/modules/*/kernel/drivers/gpu/drm/i915/i915.ko.zst.orig; do
        [ -e "$d" ] || continue
        abi="${d#/lib/modules/}"; abi="${abi%%/*}"
        restore_one "$abi"
        found=1
    done
    [ "$found" = 1 ] || { echo "No backups found anywhere under /lib/modules." >&2; exit 1; }
fi

echo
echo "Reboot to load the stock i915 module."
