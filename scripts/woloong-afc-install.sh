#!/bin/bash
# Woloong-klipperScreen: 将仓内 AFC 插件物料落位到 Klipper，幂等。
set -u
KS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${HOME}/printer_data/config"
EXTRAS="${HOME}/klipper/klippy/extras"
PC="${CFG}/printer.cfg"
log(){ echo "[woloong-afc] $*"; }

[ -f "${PC}" ] || { log "no printer.cfg, skip"; exit 0; }
grep -qE '^\[extruder' "${PC}" || { log "no extruder, skip"; exit 0; }
[ -d "${KS_DIR}/afc/extras" ] || { log "no afc extras, skip"; exit 0; }

mkdir -p "${EXTRAS}" "${CFG}/AFC" "${CFG}/AFC/macros"
for f in "${KS_DIR}"/afc/extras/*.py; do
  [ -f "${f}" ] || continue
  [ "$(basename "${f}")" = "__init__.py" ] && continue
  cp -f "${f}" "${EXTRAS}/"
done
cp -f "${KS_DIR}"/afc/config/AFC*.cfg "${CFG}/AFC/" 2>/dev/null || true
cp -f "${KS_DIR}"/afc/config/macros/*.cfg "${CFG}/AFC/macros/" 2>/dev/null || true
if [ ! -f "${CFG}/AFC/AFC.var.unit" ]; then
  cat > "${CFG}/AFC/AFC.var.unit" <<'JSON'
{
  "system": {
    "current_load": null,
    "num_units": 0,
    "num_lanes": 0,
    "num_extruders": 0,
    "extruders": {},
    "bypass": { "enabled": false }
  }
}
JSON
fi
if ! grep -qE '^\[include AFC/\*\.cfg\]' "${PC}"; then
  printf '\n[include AFC/*.cfg]\n' >> "${PC}"
fi
chown -R 1000:1000 "${CFG}/AFC" "${EXTRAS}" 2>/dev/null || true
log "AFC addon installed"
