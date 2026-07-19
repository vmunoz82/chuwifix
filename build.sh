#!/bin/bash
# Builds a patched i915.ko inside the prepared source tree.
set -e
set -o pipefail

KREL=${KREL:-6.17.0-22-generic}
HDR=/usr/src/linux-headers-${KREL}
SRC=/work/build/src

cd "$SRC"

echo "=== Stage 1: Configure kernel tree ==="
cp "$HDR/.config" .config
cp "$HDR/Module.symvers" Module.symvers
make olddefconfig

echo
echo "=== Stage 2: modules_prepare ==="
make -j"$(nproc)" KERNELRELEASE="$KREL" modules_prepare

echo
echo "=== Stage 3: Build i915 module ==="
make -j"$(nproc)" KERNELRELEASE="$KREL" \
    M=drivers/gpu/drm/i915 modules

echo
echo "=== Stage 4: Verify ==="
ls -la drivers/gpu/drm/i915/i915.ko
# `set -o pipefail` + `set -e` turn the SIGPIPE from head/grep closing the
# pipe early into a fatal 141, even though the build already succeeded.
# Guard these cosmetic verify lines so they can never abort the script.
modinfo drivers/gpu/drm/i915/i915.ko | head -10 || true
echo
echo "=== New strings of interest ==="
strings drivers/gpu/drm/i915/i915.ko | grep -iE "DSI link not ready|LP clock during LPM|Blanking packets during BLLP|EoT packet" || true
