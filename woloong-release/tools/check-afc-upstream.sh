#!/bin/bash
# ============================================================================
# check-afc-upstream.sh —— AFC 面板 vendor 落后审计（仅告警，不阻断发布）
#   VENDOR.md 的 pin 与上游 main head 比较；落后时退出码 1（CI 用 continue-on-error）
# ============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1        # → woloong-release/
ROOT="$(cd .. && pwd)"
V="$ROOT/VENDOR.md"
UP="https://github.com/ArmoredTurtle/AFC-Klipper-Screen-Add-On.git"

[ -f "$V" ] || { echo "[FAIL] 缺 VENDOR.md"; exit 2; }
PIN=$(grep -oE '^\| pin \| `[0-9a-f]{40}`' "$V" | grep -oE '[0-9a-f]{40}' | head -1)
[ -n "$PIN" ] || { echo "[FAIL] VENDOR.md 里找不到 pin"; exit 2; }

HEAD=$(git ls-remote "$UP" refs/heads/main 2>/dev/null | cut -f1)
if [ -z "$HEAD" ]; then
  echo "[SKIP] 取不到上游 main（离线？）"; exit 0
fi

echo "AFC vendor pin : $PIN"
echo "AFC 上游 head  : $HEAD"
if [ "$PIN" = "$HEAD" ]; then
  echo "[OK] AFC 面板 vendor 与上游 main 一致 ✓"
  exit 0
fi
echo "[BEHIND] AFC 面板 vendor 落后上游 —— 需要时执行："
echo "  python3 woloong-release/tools/sync-afc-panel.py --latest"
echo "  （冲突即停，按 VENDOR.md 的说明人工重锚定后提交）"
exit 1
