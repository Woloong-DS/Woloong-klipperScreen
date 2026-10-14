#!/bin/bash
# 按 assets.manifest.tsv 校验工作区中的 woloong 定制文件是否完整
set -u
cd "$(dirname "$0")/.." || exit 1
root="$(cd .. && pwd)"
fail=0; ok=0
while IFS=$'\t' read -r sha rel; do
  [ -z "${sha:-}" ] && continue
  f="$root/$rel"
  if [ ! -f "$f" ]; then echo "  MISSING  $rel"; fail=$((fail+1)); continue; fi
  got=$(sha256sum "$f" | cut -c1-64)
  if [ "$got" = "$sha" ]; then ok=$((ok+1)); else echo "  MISMATCH $rel"; fail=$((fail+1)); fi
done < <(tr -d '\r' < assets.manifest.tsv)
echo "verify-assets: ok=$ok fail=$fail"
[ "$fail" -eq 0 ] || exit 1
