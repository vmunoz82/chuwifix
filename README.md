# i915 DSI Half-Screen Fix — Ubuntu 24.04 / 6.17 HWE

Fixes the Intel Alder Lake-N (N150) half-screen issue (CHUWI MiniBook X) by backporting upstream i915 DSI clock-lane patches.

## Quick Start

**Prerequisites:**
- Ubuntu 24.04 with 6.17 HWE kernel (`uname -r` returns `6.17.0-XX-generic`)
- Secure Boot disabled
- Docker installed
- ≥10 GB free disk space
- At least one other bootable kernel as fallback

**Apply the fix:**
```bash
cd /path/to/chuwifix
docker build -t chuwi-i915-build .
sudo ./patch-running-kernel.sh
sudo reboot
```

## Verify

After reboot, both must be identical:
```bash
cat /sys/module/i915/srcversion
modinfo i915 | awk '/srcversion/{print $2}'
```

Confirm patch is installed:
```bash
sudo zstdcat /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/i915/i915.ko.zst | \
  strings | grep -E 'LP clock during LPM|Blanking packets during BLLP|EoT packet'
```

## How It Works

- **Issue:** Panel shows only right half after lid close, suspend, or DPMS
- **Root cause:** DSI clock lane stays in high-speed mode during low-power transitions → link timeout
- **Fix:** Set `LP_CLK_DURING_LPM` bit when VBT requests it (upstream commit e8a7efa81d73)

## Patches

Six backported upstream patches applied to `drivers/gpu/drm/i915/display/icl_dsi.c`:

| Commit | Description |
|--------|-------------|
| `906cbdc1fffa` | VBT 219+ bitfield definitions (backported as 0000-add-vbt-fields.patch) |
| `0b475e91ecc2` | DSC horizontal timing in command mode |
| `ca7fc6a8ae28` | Rename eotp_pkt → eot_pkt |
| `81ec9556ad69` | Declare clock_stop as boolean |
| `765a2635cd25` | Fill BLLP with blanking packets if VBT requests |
| `e8a7efa81d73` | **Place clock into LP during LPM if VBT requests** ← actual fix |

## Rollback

```bash
sudo ./restore-original-i915.sh
sudo reboot
```

## Tested

- Ubuntu 24.04 noble / linux-hwe-6.17
- CHUWI MiniBook X (N150) with Intel Alder Lake-N iGPU
- Confirmed working on kernels: 6.17.0-35-generic, 6.17.0-40-generic

## References

- [freedesktop.org — drm/i915/kernel#10334](https://gitlab.freedesktop.org/drm/i915/kernel/-/issues/10334)
- [lore.kernel.org — Ville Syrjälä DSI fixes series](https://lore.kernel.org/all/20260326111814.9800-1-ville.syrjala@linux.intel.com/)
- [kernel.org cgit — upstream commits](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git)
