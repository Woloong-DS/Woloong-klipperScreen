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
#   4) 确保 AFC 需要的 Moonraker namespaces：afc_stats（统计）与 lane_data
#      （每 lane 数据）。安装/启用 include、KSC 启动发现 [afc]、Klipper reload
#      之前都必须就绪；lane_data 被 AFC 的 PREP 清空后由 KSC 运行期 watcher
#      重建。Moonraker 不可达 -> ERROR + 非零退出，绝不打印 installed。
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
#   cp / 写 printer.cfg / 写 AFC.var.unit / 四项校验 / afc_stats/lane_data
#   namespace 任一失败 -> **非零退出**，且绝不打印 "AFC addon installed"。
#   服务单元里 ExecStartPre 带 '-' 前缀，所以配置目录只读时 KSC 仍能启动
#   （失败留在 journal，不再假成功）；namespace 失败会在下次 KSC 启动时重试。
# ============================================================================
set -euo pipefail

KS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CFG="${HOME}/printer_data/config"
PC="${CFG}/printer.cfg"
AFC_SRC="${KS_DIR}/afc"
VAR="${CFG}/AFC/AFC.var.unit"
MR="http://127.0.0.1:7125"
INCLUDE_LINE='[include AFC/*.cfg]'

log()   { printf '[woloong-afc] %s\n' "$*"; }
warn()  { printf '[woloong-afc] WARN: %s\n' "$*" >&2; }
error() { printf '[woloong-afc] ERROR: %s\n' "$*" >&2; }
die()   { printf '[woloong-afc] FAIL: %s\n' "$*" >&2; exit 1; }

# Klipper 实体仓库：Woloong 镜像为 ~/woloong-klipper（~/klipper 只是兼容软链）。
# 必须在真实仓库上写 .git/info/exclude，避免 AFC extras 被判 dirty。
KLIPPER_DIR=""
for _cand in "${HOME}/woloong-klipper" "${HOME}/klipper"; do
  if [ -d "${_cand}/klippy/extras" ]; then
    KLIPPER_DIR="${_cand}"
    break
  fi
done
# 安装必须找到 Klipper；卸载允许没有 Klipper（此时只做 include/exclude 清理）
if [ -n "${KLIPPER_DIR}" ]; then
  EXTRAS="${KLIPPER_DIR}/klippy/extras"
else
  EXTRAS=""
fi

# 真正的挤出机段：[extruder] 或 [extruder1]/[extruder2]...
# 不匹配 [extruder_stepper x]（它不创建 toolhead 挤出机）或注释行。
has_extruder() {
  grep -qE '^[[:space:]]*\[extruder[0-9]*\]([[:space:]]|$)' "${PC}"
}
include_present() {
  grep -qE '^\[include[[:space:]]+AFC/\*\.cfg\][[:space:]]*$' "${PC}"
}

# ---- Klipper .git/info/exclude（AFC extras 属正常部署，但不得判 dirty）----
# 精确模式：只忽略 AFC 包安装的 extras，不影响用户的其它未跟踪文件。
AFC_EXCLUDE_BEGIN='# >>> woloong-afc extras (managed by woloong-afc-install.sh)'
AFC_EXCLUDE_END='# <<< woloong-afc extras'
AFC_EXCLUDE_PATTERN_AFC='klippy/extras/AFC*.py'
AFC_EXCLUDE_PATTERN_TEMP='klippy/extras/temperature_oams.py'

klipper_has_git() {
  [ -d "${KLIPPER_DIR}/.git" ]
}

klipper_exclude_file() {
  printf '%s/.git/info/exclude' "${KLIPPER_DIR}"
}

# 安装/启用 extras 时调用；幂等。写失败 -> die（否则仓库会被判 dirty）
add_afc_exclude() {
  if ! klipper_has_git; then
    warn "Klipper 仓库无 .git（${KLIPPER_DIR}）；跳过 exclude，git status 不适用"
    return 0
  fi
  local ex
  ex="$(klipper_exclude_file)"
  mkdir -p "$(dirname "${ex}")" || die "cannot create ${ex} dir"
  [ -f "${ex}" ] || : > "${ex}" || die "cannot create ${ex}"
  if grep -qF "${AFC_EXCLUDE_BEGIN}" "${ex}"; then
    if ! grep -qxF "${AFC_EXCLUDE_PATTERN_AFC}" "${ex}" \
       || ! grep -qxF "${AFC_EXCLUDE_PATTERN_TEMP}" "${ex}"; then
      die "exclude managed block incomplete: ${ex}"
    fi
    log "AFC extras 已在 .git/info/exclude（幂等）"
    return 0
  fi
  {
    printf '\n%s\n' "${AFC_EXCLUDE_BEGIN}"
    printf '%s\n' "${AFC_EXCLUDE_PATTERN_AFC}"
    printf '%s\n' "${AFC_EXCLUDE_PATTERN_TEMP}"
    printf '%s\n' "${AFC_EXCLUDE_END}"
  } >> "${ex}" || die "write failed: ${ex}"
  grep -qxF "${AFC_EXCLUDE_PATTERN_AFC}" "${ex}" || die "exclude verify failed: AFC pattern"
  grep -qxF "${AFC_EXCLUDE_PATTERN_TEMP}" "${ex}" || die "exclude verify failed: temperature_oams"
  log "已写 ${ex}（AFC*.py + temperature_oams.py；精确模式）"
  return 0
}

# 卸载时撤销：只删本工具的 managed block 与两条精确模式，保留用户其它条目
remove_afc_exclude() {
  if ! klipper_has_git; then
    warn "Klipper 仓库无 .git（${KLIPPER_DIR}）；跳过 exclude 撤销"
    return 0
  fi
  local ex tmp
  ex="$(klipper_exclude_file)"
  [ -f "${ex}" ] || return 0
  tmp="$(mktemp "${ex}.XXXXXX")" || die "mktemp failed: ${ex}"
  awk -v b="${AFC_EXCLUDE_BEGIN}" -v e="${AFC_EXCLUDE_END}" \
      -v p1="${AFC_EXCLUDE_PATTERN_AFC}" -v p2="${AFC_EXCLUDE_PATTERN_TEMP}" '
    $0 == b {skip=1; next}
    $0 == e {skip=0; next}
    skip {next}
    $0 == p1 {next}
    $0 == p2 {next}
    {print}
  ' "${ex}" > "${tmp}" || { rm -f "${tmp}"; die "awk failed: ${ex}"; }
  cat "${tmp}" > "${ex}" || { rm -f "${tmp}"; die "write failed: ${ex}"; }
  rm -f "${tmp}"
  if grep -qxF "${AFC_EXCLUDE_PATTERN_AFC}" "${ex}" \
     || grep -qxF "${AFC_EXCLUDE_PATTERN_TEMP}" "${ex}" \
     || grep -qF "${AFC_EXCLUDE_BEGIN}" "${ex}"; then
    die "exclude revoke verify failed: ${ex}"
  fi
  log "已撤销 ${ex} 的 AFC exclude 条目"
  return 0
}

# ---- Moonraker namespaces（AFC 运行时 DB；缺失 -> AFC.log 404）-------------
# AFC 实际使用：
#   afc_stats : GET ?namespace=afc_stats（统计值；哨兵 key=init）
#   lane_data : GET ?namespace=lane_data（每 lane 数据）；AFC.delete_lane_data()
#               在每个 PREP 删除该 namespace 的**全部 key** -> Moonraker 丢弃
#               空 namespace -> 下一次 PREP 又 404。
# 因此：安装/启动时先建两个 namespace；KSC 运行期间再跑一个轻量 watcher，
# 在 AFC 清理后立刻把 lane_data 重建（否则 Klipper 每次 restart 都会 404）。
MR_WAIT="${WO_AFC_MOONRAKER_WAIT:-20}"   # 秒；0 = 只尝试一次（夹具用）
case "${MR_WAIT}" in
  ''|*[!0-9]*) MR_WAIT=20 ;;   # 非数字环境变量回退默认，避免死循环
esac
AFCS_NS="afc_stats"
AFCS_KEY="init"
LANE_NS="lane_data"
LANE_KEY="__woloong_init__"
NS_WATCH_INTERVAL="${WO_AFC_NS_WATCH_INTERVAL:-2}"
case "${NS_WATCH_INTERVAL}" in
  ''|*[!0-9]*) NS_WATCH_INTERVAL=2 ;;
esac

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

# 与 AFC 相同的 namespace-only GET（AFC_utils 的 get_afc_stats / delete_lane_data）
ns_ok() {
  local ns="$1"
  curl -fsS -m 3 "${MR}/server/database/item?namespace=${ns}" 2>/dev/null \
    | grep -qE "\"namespace\"[[:space:]]*:[[:space:]]*\"${ns}\""
}

ns_create() {
  local ns="$1" key="$2"
  curl -fsS -m 5 -X POST "${MR}/server/database/item" \
    -H "Content-Type: application/json" \
    -d "{\"namespace\":\"${ns}\",\"key\":\"${key}\",\"value\":{}}" >/dev/null 2>&1
}

# 幂等确保 namespace；不可达/失败返回非零（调用方必须 die）
ensure_ns() {
  local ns="$1" key="$2" label="$3"
  if ! command -v curl >/dev/null 2>&1; then
    error "${label} namespace NOT initialized: curl unavailable"
    return 1
  fi
  if ! wait_for_moonraker; then
    error "${label} namespace NOT initialized: Moonraker unreachable at ${MR} (waited ${MR_WAIT}s)"
    return 1
  fi
  if ns_ok "${ns}"; then
    log "${label} namespace ready (existing)"
    return 0
  fi
  if ! ns_create "${ns}" "${key}"; then
    error "${label} namespace NOT initialized: POST /server/database/item failed"
    return 1
  fi
  if ! ns_ok "${ns}"; then
    error "${label} namespace NOT initialized: verification GET failed"
    return 1
  fi
  log "${label} namespace created"
  return 0
}

# ---- 轻量 watcher：AFC 每次 PREP 清空 lane_data 后把它重建 ------------------
ns_watch_log() {
  if command -v logger >/dev/null 2>&1; then
    logger -t woloong-afc "$*" 2>/dev/null || true
  fi
}

ensure_ns_quiet() {
  local ns="$1" key="$2"
  if ns_ok "${ns}"; then
    return 0
  fi
  if ns_create "${ns}" "${key}" && ns_ok "${ns}"; then
    ns_watch_log "${ns} namespace re-created (AFC cleanup / Moonraker drop)"
    return 0
  fi
  ns_watch_log "WARN: ${ns} namespace re-create failed"
  return 1
}

ns_watch_loop() {
  local i=0 iters="${WO_AFC_NS_WATCH_ITERATIONS:-0}"
  case "${iters}" in
    ''|*[!0-9]*) iters=0 ;;
  esac
  while :; do
    if moonraker_up; then
      ensure_ns_quiet "${AFCS_NS}" "${AFCS_KEY}" || true
      ensure_ns_quiet "${LANE_NS}" "${LANE_KEY}" || true
    fi
    i=$((i + 1))
    if [ "${iters}" -gt 0 ] && [ "${i}" -ge "${iters}" ]; then
      return 0
    fi
    sleep "${NS_WATCH_INTERVAL}"
  done
}

start_ns_watch() {
  [ "${WO_AFC_NS_WATCH:-1}" = "1" ] || return 0
  local pf="${HOME}/printer_data/.woloong-afc-ns.pid" old=""
  if [ -f "${pf}" ]; then
    old="$(cat "${pf}" 2>/dev/null || true)"
  fi
  if [ -n "${old}" ] && [ -r "/proc/${old}/cmdline" ] \
     && tr '\0' ' ' < "/proc/${old}/cmdline" 2>/dev/null | grep -q -- '--ns-watch'; then
    return 0
  fi
  nohup bash "${KS_DIR}/scripts/woloong-afc-install.sh" --ns-watch >/dev/null 2>&1 &
  printf '%s\n' "$!" > "${pf}" 2>/dev/null || true
}

# ---- 卸载：撤 include / 删本包原样 extras / 撤销 exclude --------------------
# 关键顺序：先撤 include，再删 extras；否则 [afc] 无实现会导致 Klipper halted。
# 只删与 KSC 包逐字节一致且未被 git 跟踪的文件；用户修改/上游/跟踪文件保留。
uninstall_afc() {
  local pf old n=0 kept=0
  pf="${HOME}/printer_data/.woloong-afc-ns.pid"
  if [ -f "${pf}" ]; then
    old="$(cat "${pf}" 2>/dev/null || true)"
    if [ -n "${old}" ] && [ -r "/proc/${old}/cmdline" ] \
       && tr '\0' ' ' < "/proc/${old}/cmdline" 2>/dev/null | grep -q -- '--ns-watch'; then
      kill "${old}" 2>/dev/null || true
    fi
    rm -f "${pf}" 2>/dev/null || true
  fi

  if [ -f "${PC}" ] && include_present; then
    sed -i -E '\|^\[include[[:space:]]+AFC/\*\.cfg\][[:space:]]*$|d' "${PC}" \
      || die "failed to remove ${INCLUDE_LINE} from ${PC}"
    if include_present; then
      die "post-write verify failed: AFC include still in ${PC}"
    fi
    log "已移除 ${PC} 的 ${INCLUDE_LINE}"
  fi

  if [ -n "${EXTRAS}" ] && [ -d "${AFC_SRC}/extras" ]; then
    for f in "${AFC_SRC}"/extras/*.py; do
      [ -f "${f}" ] || continue
      b="$(basename "${f}")"
      if [ "${b}" = "__init__.py" ]; then
        continue
      fi
      if [ ! -e "${EXTRAS}/${b}" ]; then
        continue
      fi
      rel="klippy/extras/${b}"
      if klipper_has_git && git -C "${KLIPPER_DIR}" ls-files --error-unmatch "${rel}" >/dev/null 2>&1; then
        warn "保留已跟踪文件：${rel}（不删除上游/用户文件）"
        kept=$((kept + 1))
        continue
      fi
      if cmp -s "${f}" "${EXTRAS}/${b}"; then
        rm -f "${EXTRAS}/${b}" || die "rm failed: ${EXTRAS}/${b}"
        n=$((n + 1))
      else
        warn "保留用户修改过的文件：${rel}（不删除用户文件）"
        kept=$((kept + 1))
      fi
    done
  fi

  remove_afc_exclude
  log "AFC extras 已移除（${n} 个）；exclude 条目已撤销"
  [ "${kept}" -eq 0 ] || warn "${kept} 个 AFC 文件被保留（用户修改/已跟踪）"
  exit 0
}

# watcher 模式：不落位物料，只维护 namespace（KSC 运行期间常驻）
if [ "${1:-}" = "--uninstall" ]; then
  uninstall_afc
fi
if [ "${1:-}" = "--ns-watch" ]; then
  ns_watch_loop
  exit 0
fi


[ -f "${PC}" ] || die "printer.cfg not found: ${PC}"
[ -n "${EXTRAS}" ] || die "Klipper dir not found (woloong-klipper/klipper)"
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

# AFC extras 已落位：写 Klipper .git/info/exclude（精确模式；安装/启用路径）
add_afc_exclude

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

# ---- 8) AFC 需要的 Moonraker namespaces：任何启用 [afc] 的路径都幂等确保 ----
# 覆盖两条路径：
#   a) 本次/之前写入 include 且 [extruder] 已配置（AFC 即将或已经加载）
#   b) KSC 启动时检测到 Klipper 已加载 [afc]（修复路径）
# afc_stats + lane_data 缺失都会让 AFC.log 刷 404；lane_data 还会被 AFC 的
# delete_lane_data() 在每次 PREP 清空，所以还要启动 watcher 持续重建。
AFC_ACTIVE=0
if afc_loaded; then
  AFC_ACTIVE=1
  log "[afc] loaded: ensuring afc_stats/lane_data namespaces"
fi
if [ "${AFC_ACTIVE}" = "1" ] || { has_extruder && include_present; }; then
  ensure_ns "${AFCS_NS}" "${AFCS_KEY}" "${AFCS_NS}" \
    || die "afc_stats namespace NOT initialized (Moonraker unreachable?)"
  ensure_ns "${LANE_NS}" "${LANE_KEY}" "${LANE_NS}" \
    || die "lane_data namespace NOT initialized (Moonraker unreachable?)"
  start_ns_watch
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
  log "AFC addon installed (4/4 checks: AFC.py, AFC.cfg, ${INCLUDE_LINE}, AFC.var.unit; afc_stats/lane_data namespaces ready)"
else
  log "AFC materials placed (4/4 checks: AFC.py, AFC.cfg, include deferred, AFC.var.unit)"
  log "printer.cfg has no [extruder]: AFC stays disabled and its menu button stays hidden"
  log "after configuring [extruder] in the web UI, restart the KlipperScreen service (Mainsail/Fluidd service panel -> KlipperScreen -> Restart) to enable AFC"
fi
exit 0
