#!/bin/bash
set -u
cd "$(dirname "$0")/.." || exit 1
base=baseline/splash_screen.py
tgt=../panels/splash_screen.py
out=patches/splash_screen.patch
diff -u "$base" "$tgt" > "$out"
rc=$?
echo "diff_rc=$rc"   # 1 = 有差异（正常）
echo "patch_lines=$(wc -l < "$out")"
echo "hunks=$(grep -c '^@@' "$out")"
head -12 "$out"
