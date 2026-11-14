#!/bin/bash
# 同步 AFC Klipper 插件上游到 afc/，不触碰 panels/AFC.py、styles、Woloong 定制。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPSTREAM="${AFC_UPSTREAM:-https://github.com/ArmoredTurtle/AFC-Klipper-Add-On.git}"
PIN="${AFC_PIN:-5ea84ea6fab75b9b49db090f309154d1e52272bb}"
[ -n "${PIN}" ] || { echo "AFC_PIN missing" >&2; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
git clone -q --filter=blob:none "${UPSTREAM}" "${TMP}/afc"
git -C "${TMP}/afc" checkout -q "${PIN}"
rm -rf "${ROOT}/afc/extras" "${ROOT}/afc/config"
cp -a "${TMP}/afc/extras" "${ROOT}/afc/extras"
cp -a "${TMP}/afc/config" "${ROOT}/afc/config"
python3 "${ROOT}/woloong-release/tools/update-assets.py" --root "${ROOT}"
bash "${ROOT}/woloong-release/tools/verify-assets.sh"
echo "AFC_ADDON_SYNC_OK pin=${PIN}"
