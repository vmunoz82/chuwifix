#!/bin/bash
# One-shot rebuild + install of the patched i915 module for the *currently running* kernel ABI.
# Re-run this after every kernel upgrade.
#
# Pre-requisites:
#   - Docker is installed and the chuwi-i915-build image exists (build with `docker build -t chuwi-i915-build .`)
#   - linux-headers-$(uname -r) is installed
#   - Secure Boot is OFF (or the resulting module would need to be MOK-signed)
#   - sudo
set -euo pipefail
cd "$(dirname "$0")"

ABI="${ABI:-$(uname -r)}"             # e.g. 6.17.0-23-generic
ABI_NUM="${ABI%-generic}"             # e.g. 6.17.0-23
ABI_DEB="${ABI_NUM}.${ABI_NUM##*-}~24.04.1"   # e.g. 6.17.0-23.23~24.04.1
KVER_BASE="${ABI_NUM%-*}"             # e.g. 6.17.0
URL=https://launchpad.net/ubuntu/+archive/primary/+files

echo "[*] target ABI: $ABI  (deb version: $ABI_DEB)"

# --- 0. Already patched? ----------------------------------------------------
DEST="/lib/modules/${ABI}/kernel/drivers/gpu/drm/i915/i915.ko.zst"
if [ -f "$DEST" ] && sudo zstdcat "$DEST" | strings | grep -q 'LP clock during LPM'; then
    echo "[*] $DEST already contains the patch — nothing to do."
    exit 0
fi

# --- 1. Pre-flight ----------------------------------------------------------
[ -d "/usr/src/linux-headers-${ABI}" ] || { echo "[!] linux-headers-${ABI} not installed"; exit 1; }
docker image inspect chuwi-i915-build:latest >/dev/null 2>&1 \
    || { echo "[!] Docker image 'chuwi-i915-build' missing — run 'docker build -t chuwi-i915-build .' first"; exit 1; }

# --- 2. Fetch source (only if missing) -------------------------------------
mkdir -p build
cd build
DSC="linux-hwe-6.17_${ABI_DEB}.dsc"
DIFF="linux-hwe-6.17_${ABI_DEB}.diff.gz"
ORIG="linux-hwe-6.17_${KVER_BASE}.orig.tar.gz"

[ -f "$DSC"  ] || curl -fsSL "$URL/$DSC"  -o "$DSC"
[ -f "$DIFF" ] || curl -fsSL "$URL/$DIFF" -o "$DIFF"
[ -f "$ORIG" ] || curl -fsSL "$URL/$ORIG" -o "$ORIG"

echo "[*] verifying SHA256s against .dsc..."
# Match each checksum by exact filename — the order of entries under
# Checksums-Sha256 varies between .dsc files (some list orig before diff).
expected_diff=$(awk -v f="$DIFF" '/Checksums-Sha256:/{s=1;next} s && $3==f {print $1; exit}' "$DSC")
expected_orig=$(awk -v f="$ORIG" '/Checksums-Sha256:/{s=1;next} s && $3==f {print $1; exit}' "$DSC")
[ -n "$expected_diff" ] && [ -n "$expected_orig" ] || { echo "[!] could not read expected checksums from $DSC"; exit 1; }
echo "$expected_diff  $DIFF" | sha256sum -c -
echo "$expected_orig  $ORIG" | sha256sum -c -

# --- 3. Extract source (fresh copy each run) -------------------------------
echo "[*] extracting source tree..."
sudo rm -rf src
docker run --rm -v "$PWD/..":/work -w /work/build chuwi-i915-build dpkg-source -x "$DSC" src >/dev/null
sudo chown -R "$(id -u):$(id -g)" src

# --- 4. Apply patches ------------------------------------------------------
echo "[*] applying patches..."
cd src
for p in "$(dirname "$0")"/patches/000*.patch; do
    patch -p1 < "$p" >/dev/null
    echo "    [ok] $(basename "$p")"
done
cd ..

# --- 5. Build (only the i915 module) ----------------------------------------
echo "[*] building i915 module against /usr/src/linux-headers-${ABI} ..."
docker run --rm \
    -e KREL="${ABI}" \
    -v "$PWD/..":/work \
    -v "/usr/src/linux-headers-${ABI}":"/usr/src/linux-headers-${ABI}":ro \
    -w /work \
    chuwi-i915-build /work/build.sh > "../i915-build-${ABI}.log" 2>&1

KO="src/drivers/gpu/drm/i915/i915.ko"
[ -f "$KO" ] || { echo "[!] build failed — see ../i915-build-${ABI}.log"; tail -30 "../i915-build-${ABI}.log"; exit 1; }

# --- 6. Strip, compress, install -------------------------------------------
echo "[*] stripping + zstd-compressing..."
sudo chown "$(id -u):$(id -g)" "$KO"
strip --strip-debug "$KO" -o "/tmp/i915-${ABI}.ko"
zstd -19 -f -q "/tmp/i915-${ABI}.ko" -o "../i915.ko.zst.${ABI}"
rm "/tmp/i915-${ABI}.ko"

echo "[*] installing into /lib/modules/${ABI}/..."
[ -f "$DEST" ] && sudo cp -av "$DEST" "${DEST}.orig" >/dev/null
sudo install -m 0644 -o root -g root "../i915.ko.zst.${ABI}" "$DEST"
sudo depmod -a "${ABI}"

# --- 6b. Refresh initramfs if it ships i915 --------------------------------
# On this machine i915 IS baked into the initramfs (early-load segment), so it
# gets loaded before /lib/modules is consulted. If we don't regenerate the
# initramfs it will keep loading the STALE vanilla module and the on-disk
# patched one is never used. Only rebuild when i915 is actually present.
INITRD="/boot/initrd.img-${ABI}"
if [ -f "$INITRD" ] && sudo lsinitramfs "$INITRD" | grep -q 'drm/i915/i915\.ko'; then
    echo "[*] i915 is in ${INITRD} — regenerating initramfs..."
    sudo update-initramfs -u -k "${ABI}"
else
    echo "[*] i915 not in initramfs — skipping update-initramfs."
fi

# --- 7. Verify the patch is present in the installed file ------------------
echo "[*] verifying installed module..."
sudo zstdcat "$DEST" | strings | grep -E 'LP clock during LPM|Blanking packets during BLLP|EoT packet'

echo
echo "[done] Patched i915 installed for ${ABI}.  Reboot to activate."
