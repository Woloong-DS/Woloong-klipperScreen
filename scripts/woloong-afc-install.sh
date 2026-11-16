#!/bin/bash
# ============================================================================
# Woloong-klipperScreen — AFC 插件落位器（幂等 / fail-fast）
#
# 由 KlipperScreen.service 的 ExecStartPre 在**每次 KSC 启动前**执行。
#   1) 幂等落位 KSC 内置 AFC 物料：klippy/extras/*.py + printer_data/config/AFC/
#   2) 仅当 printer.cfg 有真正的 [extruder]/[extruderN] 时才启用
#      [include AFC/*.cfg]；无 [extruder] 时物料照落位，include 保持关闭
#      （AFC 的 klippy 模块会在 get_status 里访问真实挤出机，缺 [extruder]
#       会让整机 shutdown，所以不能只凭「物料在」就启用 include）
#   3) 首次追加 include 后，经 Moonraker 重启 Klipper 并等待 [afc] 生效，
#      这样随后启动的 KSC 能把 AFC 菜单渲染出来（否则要再重启一次 KSC）。
#   4) 确保 Moonraker 的 afc_stats namespace：安装/重启用 include 的路径、
#      以及 KSC 启动时发现 [afc] 已加载的修复路径，都必须幂等初始化。
#      Moonraker 不可达 -> ERROR + 非零退出，绝不打印 installed（不假成功）。
#
# 触发路径（用户不需要手工跑本脚本）：
#   · Web（Mainsail/Fluidd）：服务面板 -> KlipperScreen -> Restart
#     （systemctl restart KlipperScreen -> 重新执行本 ExecStartPre）
#   · KIAUH：更新/整机更新 KlipperScreen 会 stop/start 服务（同样触发）
#   · 重启设备 / 任何 `systemctl restart KlipperScreen`
#   ★ 注意：KSC 触摸屏的 "Restart KlipperScreen" 只是 os.execv 换掉
#     Python 进程（screen.py:507），**不会**重启 systemd 单元，因此不会
#     触发本脚本；首启后请用上面的 Web 服务面板动作（或 KIAUH 更新）。
#
# 失败语义（AFC-FALSE-SUCCESS，2026-11-15）：
#   cp / 写 printer.cfg / 写 AFC.var.unit / 四项校验 / afc_stats namespace
#   任一失败 -> **非零退出**，且绝不打印 "AFC addon installed"。
#   服务单元里 ExecStartPre 带 '-' 前缀，所以配置目录只读时 KSC 仍能启动
#   （失败留在 journal，不再假成功）；namespace 失败会在下次 KSC 启动时重试。
# ============================================================================
set -euo pipefail

KS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${HOME}/printer_data/config"
EXTRAS="${HOME}/klipper/klippy/extras"
PC="${CFG}/printer.cfg"
AFC_SRC="${KS_DIR}/afc"
VAR="${CFG}/AFC/AFC.var.unit"
MR="http://127.0.0.1:7125"
INCLUDE_LINE='[include AFC/*.cfg]'

log()   { printf '[woloong-afc] %s\n' "$*"; }
warn()  { printf '[woloong-afc] WARN: %s\n' "$*" >&2; }
error() { printf '[woloong-afc] ERROR: %s\n' "$*" >&2; }
die()   { printf '[woloong-afc] FAIL: %s\n' "$*" >&2; exit 1; }

# 真正的挤出机段：[extruder] 或 [extruder1]/[extruder2]...
# 不匹配 [extruder_stepper x]（它不创建 toolhead 挤出机）或注释行。
has_extruder() {
  grep -qE '^[[:space:]]*\[extruder[0-9]*\]([[:space:]]|$)' "${PC}"
}
include_present() {
  grep -qE '^\[include[[:space:]]+AFC/\*\.cfg\][[:space:]]*$' "${PC}"
}

# ---- afc_stats namespace（AFC 运行时查询 Moonraker DB；缺失 -> 404 红字）----
MR_WAIT="${WO_AFC_MOONRAKER_WAIT:-20}"   # 秒；0 = 只尝试一次（夹具用）
case "${MR_WAIT}" in
  ''|*[!0-9]*) MR_WAIT=20 ;;   # 非数字环境变量回退默认，避免死循环
esac
AFCS_NS="afc_stats"

moonraker_up() {
  curl -fsS -m 3 "${MR}/server/info" >/dev/null 2>&1
}

wait_for_moonraker() {
  local i=0
  command -v curl >/dev/null 2>&1 || return 1
  while :; do
    if moonraker_up; then
      return 0
    fi
    if [ "${i}" -ge "${MR_WAIT}" ]; then
      return 1
    fi
    i=$((i + 1))
    sleep 1
  done
}

# Klipper 当前是否已加载 [afc]（configfile.config 的段名是小写）
afc_loaded() {
  command -v curl >/dev/null 2>&1 || return 1
  curl -fsS -m 3 "${MR}/printer/objects/query?configfile" 2>/dev/null \
    | grep -qE '"afc"[[:space:]]*:[[:space:]]*\{'
}

# 与 AFC_utils.get_afc_stats() 相同的查询：namespace-only GET
afc_stats_namespace_ok() {
  curl -fsS -m 3 "${MR}/server/database/item?namespace=${AFCS_NS}" 2>/dev/null \
    | grep -qE "\"namespace\"[[:space:]]*:[[:space:]]*\"${AFCS_NS}\""
}

# 幂等确保 namespace；不可达/失败返回非零（调用方必须 die）
ensure_afc_stats() {
  if ! command -v curl >/dev/null 2>&1; then
    error "afc_stats namespace NOT initialized: curl unavailable"
    return 1
  fi
  if ! wait_for_moonraker; then
    error "afc_stats namespace NOT initialized: Moonraker unreachable at ${MR} (waited ${MR_WAIT}s)"
    return 1
  fi
  if afc_stats_namespace_ok; then
    log "afc_stats namespace ready (existing)"
    return 0
  fi
  if ! curl -fsS -m 5 -X POST "${MR}/server/database/item" \
      -H "Content-Type: application/json" \
      -d "{\"namespace\":\"${AFCS_NS}\",\"key\":\"init\",\"value\":{}}" >/dev/null 2>&1; then
    error "afc_stats namespace NOT initialized: POST /server/database/item failed"
    return 1
  fi
  if ! afc_stats_namespace_ok; then
    error "afc_stats namespace NOT initialized: verification GET failed"
    return 1
  fi
  log "afc_stats namespace created"
  return 0
}

[ -f "${PC}" ] || die "printer.cfg not found: ${PC}"
[ -d "${AFC_SRC}/extras" ] || die "AFC extras missing in KSC checkout: ${AFC_SRC}/extras"
[ -d "${AFC_SRC}/config" ] || die "AFC config missing in KSC checkout: ${AFC_SRC}/config"

mkdir -p "${EXTRAS}" || die "cannot create ${EXTRAS}"
mkdir -p "${CFG}/AFC/macros" || die "cannot create ${CFG}/AFC/macros"

# ---- 1) klippy extras（逐文件 cp + 逐文件 cmp 校验）-----------------------
n_extras=0
for f in "${AFC_SRC}"/extras/*.py; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  if [ "$b" = "__init__.py" ]; then
    continue
  fi
  dst="${EXTRAS}/${b}"
  cp -f "$f" "$dst" || die "cp failed: $f -> $dst"
  cmp -s "$f" "$dst" || die "post-copy verify failed: $dst"
  n_extras=$((n_extras + 1))
done
(( n_extras > 0 )) || die "no AFC klippy extras (*.py) in ${AFC_SRC}/extras"

# ---- 2) AFC 配置（AFC*.cfg + macros/*.cfg）--------------------------------
n_cfg=0
for f in "${AFC_SRC}"/config/AFC*.cfg; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  cp -f "$f" "${CFG}/AFC/${b}" || die "cp failed: $f -> ${CFG}/AFC/${b}"
  cmp -s "$f" "${CFG}/AFC/${b}" || die "post-copy verify failed: ${CFG}/AFC/${b}"
  n_cfg=$((n_cfg + 1))
done
(( n_cfg > 0 )) || die "no AFC config (AFC*.cfg) in ${AFC_SRC}/config"

n_macro=0
for f in "${AFC_SRC}"/config/macros/*.cfg; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  cp -f "$f" "${CFG}/AFC/macros/${b}" || die "cp failed: $f -> ${CFG}/AFC/macros/${b}"
  cmp -s "$f" "${CFG}/AFC/macros/${b}" || die "post-copy verify failed: ${CFG}/AFC/macros/${b}"
  n_macro=$((n_macro + 1))
done
(( n_macro > 0 )) || die "no AFC macros (macros/*.cfg) in ${AFC_SRC}/config"

# ---- 3) AFC.var.unit（首次生成；已存在则不覆盖用户数据）------------------
if [ ! -f "${VAR}" ]; then
  cat > "${VAR}" <<'JSON' || die "write failed: ${VAR} (read-only?)"
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
[ -s "${VAR}" ] || die "AFC.var.unit missing or empty: ${VAR}"
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); assert isinstance(d, dict)' "${VAR}" \
    || die "invalid AFC.var.unit (not a JSON object): ${VAR}"
else
  grep -q '"system"' "${VAR}" || die "invalid AFC.var.unit (missing system): ${VAR}"
fi

# ---- 4) 关闭未配置坐标的宏（默认 -99 会刷 AFC ERROR）---------------------
if [ -f "${CFG}/AFC/AFC.cfg" ]; then
  sed -i -E 's/^(tool_cut|park|poop|kick|wipe): True/\1: False/' "${CFG}/AFC/AFC.cfg" \
    || die "failed to update ${CFG}/AFC/AFC.cfg (read-only?)"
fi

# ---- 5) include：有挤出机才启用；无挤出机则确保关闭 ----------------------
NEW_INCLUDE=0
if has_extruder; then
  if ! include_present; then
    printf '\n%s\n' "${INCLUDE_LINE}" >> "${PC}" || die "write failed: ${PC} (read-only?)"
    if ! include_present; then
      die "post-write verify failed: ${INCLUDE_LINE} not in ${PC}"
    fi
    NEW_INCLUDE=1
  fi
else
  if include_present; then
    sed -i -E '\|^\[include[[:space:]]+AFC/\*\.cfg\][[:space:]]*$|d' "${PC}" \
      || die "failed to disable AFC include in ${PC} (read-only?)"
    if include_present; then
      die "post-write verify failed: AFC include still in ${PC}"
    fi
    log "printer.cfg has no [extruder]: removed ${INCLUDE_LINE}"
  fi
fi

# ---- 6) 首次启用后重启 Klipper，让 [afc] 在 KSC 启动前生效 ----------------
# 只在「本次新加 include」时做；正在打印/暂停时绝不重启（保护打印）。
klipper_reload_for_afc() {
  local state ps i
  command -v curl >/dev/null 2>&1 || { warn "curl unavailable: [afc] will load on next Klipper start"; return 0; }
  state="$(curl -fsS -m 3 "${MR}/printer/info" 2>/dev/null \
    | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  if [ "${state}" != "ready" ]; then
    warn "Klipper state=${state:-unknown}: [afc] will load on next Klipper start"
    return 0
  fi
  ps="$(curl -fsS -m 3 "${MR}/printer/objects/query?print_stats" 2>/dev/null \
    | sed -n 's/.*"state"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  if [ "${ps}" = "printing" ] || [ "${ps}" = "paused" ]; then
    warn "print is ${ps}: skip Klipper reload ([afc] loads on next Klipper restart)"
    return 0
  fi
  log "reloading Klipper so [afc] becomes active ..."
  curl -fsS -m 5 -X POST "${MR}/machine/services/restart?service=klipper" >/dev/null 2>&1 || {
    warn "Moonraker restart request failed: [afc] will load on next Klipper start"
    return 0
  }
  i=0
  while [ "${i}" -lt 30 ]; do
    if curl -fsS -m 3 "${MR}/printer/objects/query?configfile" 2>/dev/null \
      | grep -qE '"afc"[[:space:]]*:[[:space:]]*\{'; then
      log "Klipper reloaded: [afc] section active"
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  warn "[afc] not visible after 30s: check Klipper log / AFC configuration"
  return 0
}

# ---- 7) 安装后四项校验（任一失败 -> 非零退出，绝不打印成功）--------------
# 1/4
[ -s "${EXTRAS}/AFC.py" ] || die "verify 1/4 failed: ${EXTRAS}/AFC.py missing/empty"
cmp -s "${AFC_SRC}/extras/AFC.py" "${EXTRAS}/AFC.py" || die "verify 1/4 failed: AFC.py differs from package"
# 2/4
[ -s "${CFG}/AFC/AFC.cfg" ] || die "verify 2/4 failed: ${CFG}/AFC/AFC.cfg missing/empty"
grep -qE '^\[AFC\]' "${CFG}/AFC/AFC.cfg" || die "verify 2/4 failed: AFC.cfg has no [AFC] section"
# 3/4
if has_extruder; then
  include_present || die "verify 3/4 failed: printer.cfg missing ${INCLUDE_LINE}"
else
  if include_present; then
    die "verify 3/4 failed: ${INCLUDE_LINE} present without [extruder]"
  fi
fi
# 4/4
[ -s "${VAR}" ] || die "verify 4/4 failed: ${VAR} missing/empty"

# ---- 8) afc_stats namespace：任何启用 [afc] 的路径都幂等确保 ----------------
# 覆盖两条路径：
#   a) 本次/之前写入 include 且 [extruder] 已配置（AFC 即将或已经加载）
#   b) KSC 启动时检测到 Klipper 已加载 [afc]（1610-u 的修复路径）
# Moonraker 不可达 / API 失败 -> ensure 返回非零 -> die（不打印 installed）。
AFC_ACTIVE=0
if afc_loaded; then
  AFC_ACTIVE=1
  log "[afc] loaded: ensuring afc_stats namespace"
fi
if [ "${AFC_ACTIVE}" = "1" ] || { has_extruder && include_present; }; then
  ensure_afc_stats || die "afc_stats namespace NOT initialized (Moonraker unreachable?)"
fi

# ---- 9) 首次启用后重启 Klipper，让 [afc] 在 KSC 启动前生效 ----------------
# 只在「本次新加 include」时做；正在打印/暂停时绝不重启（保护打印）。
if [ "${NEW_INCLUDE}" = "1" ]; then
  if [ "${WO_AFC_KLIPPER_RESTART:-1}" = "0" ]; then
    warn "WO_AFC_KLIPPER_RESTART=0: [afc] will load on next Klipper start"
  else
    klipper_reload_for_afc
  fi
fi

# ---- 10) 成功日志（仅在四项校验 + namespace 全部通过之后）-----------------
if [ "$(id -u)" = "0" ]; then
  chown -R 1000:1000 "${CFG}/AFC" "${EXTRAS}" 2>/dev/null || true
fi

if has_extruder; then
  log "AFC addon installed (4/4 checks: AFC.py, AFC.cfg, ${INCLUDE_LINE}, AFC.var.unit; afc_stats namespace ready)"
else
  log "AFC materials placed (4/4 checks: AFC.py, AFC.cfg, include deferred, AFC.var.unit)"
  log "printer.cfg has no [extruder]: AFC stays disabled and its menu button stays hidden"
  log "after configuring [extruder] in the web UI, restart the KlipperScreen service (Mainsail/Fluidd service panel -> KlipperScreen -> Restart) to enable AFC"
fi
exit 0
