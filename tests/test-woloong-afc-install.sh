#!/bin/bash
# ============================================================================
# 夹具：woloong-afc-install.sh（AFC 首启落位 / fail-fast / Moonraker namespaces）
#
# 覆盖：
#   1) 无 [extruder]：物料落位，include 关闭（不打印 installed；不碰 DB）
#   2) 有 [extruder]：四项 + afc_stats + lane_data + Klipper reload；幂等
#   2b) 打印中：include 照写，但不重启 Klipper；两个 namespace 仍就绪
#   2c) [afc] 已加载但 afc_stats/lane_data 缺失 -> 两个都补建
#   2d) 两个 namespace 已存在 -> 幂等（不重复 POST）
#   2e) Moonraker 不可达（[afc] 已加载）-> 非零退出，不假成功
#   2f) Moonraker 不可达（首次安装 include）-> 非零退出，不假成功
#   2g) watcher：AFC 清空 lane_data / namespace 丢失后重建（两个都覆盖）
#   2h) watcher：Moonraker 不可达 -> 不崩、不假成功（后台维护尽力而为）
#   2i) 真实 Klipper 仓库：安装后 git status 空；exclude 精确模式
#   2j) 修改已跟踪文件仍显示 dirty（exclude 不掩盖 tracked）
#   2k) 卸载撤销 exclude、删本包 extras、保留用户文件；不用 clean -fd
#   2l) 用户改过的 AFC.py 卸载保留；Uninstall.sh 接线；脚本无 git clean
#   2m) 无 [extruder] 也落位 extras -> exclude 仍写、status 空
#   3) printer.cfg 只读：非零退出，不打印 installed
#   4) cp 失败：非零退出，不打印 installed，include 不落
#   5) known-bad（1627 旧脚本）cp 失败：必须被「成功后校验」判据抓住
#   6) known-bad（1627 旧脚本）printer.cfg 只读：必须被抓住
#   7) service 模板：ExecStartPre 带 '-'（失败不拖垮 KSC 启动）
#
# 用法：bash tests/test-woloong-afc-install.sh
# 输出：AFC_INSTALL_FIXTURES pass=N fail=N；有失败则退出码非零
# ============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
INSTALLER="$REPO/scripts/woloong-afc-install.sh"
KNOWN_BAD="$HERE/fixtures/woloong-afc-install-known-bad.sh"
TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/afc-fixtures.XXXXXX")" || exit 1
cleanup() {
  chmod -R u+w "$TMPROOT" 2>/dev/null || true
  rm -rf "$TMPROOT"
}
trap cleanup EXIT

PASS=0
FAIL=0
ok()  { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }
h()   { printf '\n== %s ==\n' "$1"; }
ck()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
ck_not() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then bad "$d"; else ok "$d"; fi; }

CASE=""; KS=""; H=""; BIN=""; CFG=""; EXTRAS=""; PC=""; KL=""

# Moonraker 桩：state 文件模拟 namespace / [afc] / 打印状态 / 可达性。
write_fake_curl() {
  cat > "$BIN/curl" <<EOF
#!/bin/sh
echo "\$*" >> "$CASE/curl.log"
if [ -f "$CASE/moonraker-down" ]; then
  exit 7
fi
ns=""
case "\$*" in
  *machine/services/restart*)
    echo x >> "$CASE/restart.log"
    : > "$CASE/afc-active"
    exit 0 ;;
  *server/database/item*)
    if printf '%s' "\$*" | grep -q -- '-X POST'; then
      case "\$*" in
        *'"key":"__woloong_init__"'*) ns=lane_data ;;
        *'"key":"init"'*) ns=afc_stats ;;
      esac
      echo "\$ns" >> "$CASE/db-post.log"
      : > "$CASE/ns-\$ns"
      printf '{"result":{"namespace":"%s","key":"init","value":{}}}\n' "\$ns"
      exit 0
    fi
    case "\$*" in
      *namespace=afc_stats*) ns=afc_stats ;;
      *namespace=lane_data*) ns=lane_data ;;
    esac
    if [ -n "\$ns" ] && [ -f "$CASE/ns-\$ns" ]; then
      printf '{"result":{"namespace":"%s","key":null,"value":{}}}\n' "\$ns"
      exit 0
    fi
    exit 22 ;;
  *server/info*)
    printf '%s\n' '{"result":{"klippy_connected":true}}'
    exit 0 ;;
  *objects/query*configfile*)
    if [ -f "$CASE/afc-active" ]; then
      printf '%s\n' '{"result":{"status":{"configfile":{"config":{"afc":{}}}}}}}'
    else
      printf '%s\n' '{"result":{"status":{"configfile":{"config":{}}}}}'
    fi
    exit 0 ;;
  *print_stats*)
    state=ready
    if [ -f "$CASE/print-state" ]; then state="\$(cat "$CASE/print-state")"; fi
    printf '{"result":{"status":{"print_stats":{"state":"%s"}}}}' "\$state"
    exit 0 ;;
  *printer/info*)
    printf '%s\n' '{"result":{"status":{"state":"ready"}}}'
    exit 0 ;;
  *)
    exit 0 ;;
esac
EOF
  chmod +x "$BIN/curl"
}

new_case() {
  CASE="$TMPROOT/$1"
  KS="$CASE/ks"
  H="$CASE/home"
  BIN="$CASE/bin"
  rm -rf "$CASE"
  mkdir -p "$KS/scripts" "$H/printer_data/config" "$H/klipper/klippy/extras" "$BIN"
  KL=""
  cp "$INSTALLER" "$KS/scripts/woloong-afc-install.sh"
  chmod +x "$KS/scripts/woloong-afc-install.sh"
  cp -R "$REPO/afc" "$KS/afc"
  CFG="$H/printer_data/config"
  EXTRAS="$H/klipper/klippy/extras"
  PC="$CFG/printer.cfg"
  write_fake_curl
}

# 真实 Klipper 仓库（~/woloong-klipper + .git），用于 exclude/status/uninstall 夹具
new_git_case() {
  CASE="$TMPROOT/$1"
  KS="$CASE/ks"
  H="$CASE/home"
  BIN="$CASE/bin"
  KL="$H/woloong-klipper"
  rm -rf "$CASE"
  mkdir -p "$KS/scripts" "$H/printer_data/config" "$KL/klippy/extras" "$BIN"
  cp "$INSTALLER" "$KS/scripts/woloong-afc-install.sh"
  chmod +x "$KS/scripts/woloong-afc-install.sh"
  cp -R "$REPO/afc" "$KS/afc"
  git -C "$KL" init -q
  git -C "$KL" config core.autocrlf false
  git -C "$KL" config core.eol lf
  git -C "$KL" config user.email fixture@woloong.local
  git -C "$KL" config user.name fixture
  printf '# upstream/user tracked file\n' > "$KL/klippy/extras/user_tracked.py"
  git -C "$KL" add klippy/extras/user_tracked.py
  git -C "$KL" commit -q -m "fixture base"
  CFG="$H/printer_data/config"
  EXTRAS="$KL/klippy/extras"
  PC="$CFG/printer.cfg"
  write_fake_curl
}

write_cfg_no_extruder() {
  cat > "$PC" <<'EOF'
[mcu]
serial: CHANGE-ME
[printer]
kinematics: none
# [extruder] 被注释掉，不算配置
[extruder_stepper e0]
step_pin: PA0
EOF
}

write_cfg_with_extruder() {
  cat > "$PC" <<'EOF'
[mcu]
serial: /dev/serial/by-id/usb-Klipper_fixture
[printer]
kinematics: none
[extruder]
step_pin: PA0
dir_pin: PA1
enable_pin: !PA2
microsteps: 16
rotation_distance: 33.5
nozzle_diameter: 0.4
filament_diameter: 1.75
heater_pin: PA3
sensor_type: EPCOS 100K B57560G104F
sensor_pin: PA4
EOF
}

run_installer() {
  OUT="$(HOME="$H" PATH="$BIN:$PATH" WO_AFC_MOONRAKER_WAIT="${WO_AFC_MOONRAKER_WAIT:-0}" \
    WO_AFC_NS_WATCH=0 bash "$KS/scripts/woloong-afc-install.sh" 2>&1)"
  RC=$?
  printf '%s\n' "$OUT" > "$CASE/out.log"
}

run_watcher_once() {
  OUT="$(HOME="$H" PATH="$BIN:$PATH" WO_AFC_MOONRAKER_WAIT=0 \
    WO_AFC_NS_WATCH_ITERATIONS=1 bash "$KS/scripts/woloong-afc-install.sh" --ns-watch 2>&1)"
  RC=$?
  printf '%s\n' "$OUT" > "$CASE/watch.log"
}

run_uninstall() {
  OUT="$(HOME="$H" PATH="$BIN:$PATH" WO_AFC_NS_WATCH=0 \
    bash "$KS/scripts/woloong-afc-install.sh" --uninstall 2>&1)"
  RC=$?
  printf '%s\n' "$OUT" > "$CASE/uninstall.log"
}

make_failing_cp() {
  local real_cp
  real_cp="$(command -v cp)"
  cat > "$BIN/cp" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    *AFC.py)
      echo "cp: simulated failure (fixture)" >&2
      exit 1 ;;
  esac
done
exec "$real_cp" "\$@"
EOF
  chmod +x "$BIN/cp"
}

has_include() { grep -qF '[include AFC/*.cfg]' "$PC"; }
no_include()  { if grep -qF '[include AFC/*.cfg]' "$PC"; then return 1; fi; return 0; }
ns_present()  { test -f "$CASE/ns-$1"; }
ns_posted()   { test -f "$CASE/db-post.log"; }
git_clean()       { [ -z "$(git -C "$KL" status --porcelain)" ]; }
exclude_has_afc() { grep -qxF 'klippy/extras/AFC*.py' "$KL/.git/info/exclude"; }
exclude_has_tmp() { grep -qxF 'klippy/extras/temperature_oams.py' "$KL/.git/info/exclude"; }
exclude_clean()   { ! grep -qF 'woloong-afc extras' "$KL/.git/info/exclude" \
                    && ! grep -qxF 'klippy/extras/AFC*.py' "$KL/.git/info/exclude" \
                    && ! grep -qxF 'klippy/extras/temperature_oams.py' "$KL/.git/info/exclude"; }


# 「成功后校验」判据：日志只说成功不算，必须文件 + include + 两个 namespace 真的在
installed_ok() {
  local rc="$1" out="$2"
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$out" | grep -q 'AFC addon installed' || return 1
  [ -s "$EXTRAS/AFC.py" ] || return 1
  cmp -s "$REPO/afc/extras/AFC.py" "$EXTRAS/AFC.py" || return 1
  [ -s "$CFG/AFC/AFC.cfg" ] || return 1
  grep -q '^\[AFC\]' "$CFG/AFC/AFC.cfg" || return 1
  grep -qF '[include AFC/*.cfg]' "$PC" || return 1
  [ -s "$CFG/AFC/AFC.var.unit" ] || return 1
  ns_present afc_stats || return 1
  ns_present lane_data || return 1
  return 0
}

deferred_ok() {
  local rc="$1" out="$2"
  [ "$rc" -eq 0 ] || return 1
  printf '%s' "$out" | grep -q 'include deferred' || return 1
  if printf '%s' "$out" | grep -q 'AFC addon installed'; then return 1; fi
  [ -s "$EXTRAS/AFC.py" ] || return 1
  [ -s "$CFG/AFC/AFC.cfg" ] || return 1
  [ -s "$CFG/AFC/AFC.var.unit" ] || return 1
  if grep -qF '[include AFC/*.cfg]' "$PC"; then return 1; fi
  if ns_present afc_stats; then return 1; fi
  if ns_present lane_data; then return 1; fi
  return 0
}

# ---------------------------------------------------------------------------
h "fixture 1: 无 [extruder] -> 物料落位、include 关闭、不碰 namespace"
new_case no-extruder
write_cfg_no_extruder
run_installer
ck "退出码 0" test "$RC" -eq 0
ck "deferred_ok（物料在 + include 关闭 + 无 installed + 无 namespace）" deferred_ok "$RC" "$OUT"
ck "AFC.py 已落位" test -s "$EXTRAS/AFC.py"
ck "AFC.cfg 已落位" test -s "$CFG/AFC/AFC.cfg"
ck "AFC.var.unit 已生成" test -s "$CFG/AFC/AFC.var.unit"
ck "include 未启用" no_include
ck_not "AFC 未启用时不初始化 namespace" ns_posted
ck "输出说明按钮仍隐藏" grep -qF 'menu button stays hidden' "$CASE/out.log"
ck "输出给出重新触发动作（Web 服务面板重启 KSC）" grep -qF 'KlipperScreen service' "$CASE/out.log"
printf '\n[include AFC/*.cfg]\n' >> "$PC"
run_installer
ck "遗留 include 在无 [extruder] 时被关闭（退出码 0）" test "$RC" -eq 0
ck "遗留 include 已移除" no_include
ck "输出说明已移除 include" grep -qF 'removed [include AFC/*.cfg]' "$CASE/out.log"
ck_not "移除遗留 include 时仍不碰 namespace" ns_posted

# ---------------------------------------------------------------------------
h "fixture 2: 有 [extruder] -> 四项 + 两个 namespace + Klipper reload + 幂等"
new_case with-extruder
write_cfg_with_extruder
run_installer
ck "installed_ok（rc0 + installed + 四项 + 两个 namespace）" installed_ok "$RC" "$OUT"
ck "输出含 4/4" grep -qF '4/4' "$CASE/out.log"
ck "afc_stats namespace 已创建" ns_present afc_stats
ck "lane_data namespace 已创建" ns_present lane_data
ck "输出说明 afc_stats created" grep -qF 'afc_stats namespace created' "$CASE/out.log"
ck "输出说明 lane_data created" grep -qF 'lane_data namespace created' "$CASE/out.log"
ck "已请求 Moonraker 重启 Klipper" test -s "$CASE/restart.log"
ck "等待到 [afc] active" grep -qF '[afc] section active' "$CASE/out.log"
ck "两个 namespace 都初始化在 Klipper 重启之前" awk '/server\/database\/item/ && /-X POST/ {p=NR} /machine\/services\/restart/ {r=NR} END {exit !(p && r && p < r)}' "$CASE/curl.log"
ck "include 已写入一行" test "$(grep -cF '[include AFC/*.cfg]' "$PC")" -eq 1
run_installer
ck "第二次退出码 0" test "$RC" -eq 0
ck "第二次未再重启 Klipper" test "$(wc -l < "$CASE/restart.log")" -eq 1
ck "第二次未重复 POST namespace" test "$(wc -l < "$CASE/db-post.log")" -eq 2
ck "include 仍只有一行（幂等）" test "$(grep -cF '[include AFC/*.cfg]' "$PC")" -eq 1

# ---------------------------------------------------------------------------
h "fixture 2b: 打印中不重启 Klipper（保护打印），namespace 仍就绪"
new_case printing-guard
write_cfg_with_extruder
printf 'printing\n' > "$CASE/print-state"
run_installer
ck "退出码 0（include 照常写入）" test "$RC" -eq 0
ck "installed_ok" installed_ok "$RC" "$OUT"
ck "afc_stats namespace 已创建" ns_present afc_stats
ck "lane_data namespace 已创建" ns_present lane_data
ck_not "未请求重启 Klipper" test -s "$CASE/restart.log"
ck "输出说明正在打印、跳过 reload" grep -qF 'skip Klipper reload' "$CASE/out.log"

# ---------------------------------------------------------------------------
h "fixture 2c: [afc] 已加载但两个 namespace 缺失 -> 都补建"
new_case ns-repair
write_cfg_with_extruder
printf '\n[include AFC/*.cfg]\n' >> "$PC"
: > "$CASE/afc-active"
run_installer
ck "退出码 0" test "$RC" -eq 0
ck "installed_ok（修复后四项 + 两个 namespace）" installed_ok "$RC" "$OUT"
ck "afc_stats 已补建" ns_present afc_stats
ck "lane_data 已补建" ns_present lane_data
ck "输出说明 afc_stats created" grep -qF 'afc_stats namespace created' "$CASE/out.log"
ck "输出说明 lane_data created" grep -qF 'lane_data namespace created' "$CASE/out.log"
ck "输出说明检测到 [afc]" grep -qF '[afc] loaded' "$CASE/out.log"
ck_not "include 已存在时不重启 Klipper" test -s "$CASE/restart.log"

# ---------------------------------------------------------------------------
h "fixture 2d: 两个 namespace 已存在 -> 幂等（不重复 POST）"
new_case ns-existing
write_cfg_with_extruder
printf '\n[include AFC/*.cfg]\n' >> "$PC"
: > "$CASE/afc-active"
: > "$CASE/ns-afc_stats"
: > "$CASE/ns-lane_data"
run_installer
ck "退出码 0" test "$RC" -eq 0
ck "installed_ok" installed_ok "$RC" "$OUT"
ck "输出说明 afc_stats existing" grep -qF 'afc_stats namespace ready (existing)' "$CASE/out.log"
ck "输出说明 lane_data existing" grep -qF 'lane_data namespace ready (existing)' "$CASE/out.log"
ck_not "未重复 POST namespace" ns_posted
ck_not "未重启 Klipper" test -s "$CASE/restart.log"

# ---------------------------------------------------------------------------
h "fixture 2e: Moonraker 不可达（[afc] 已加载）-> 非零退出、不假成功"
new_case moonraker-down-repair
write_cfg_with_extruder
printf '\n[include AFC/*.cfg]\n' >> "$PC"
: > "$CASE/afc-active"
: > "$CASE/moonraker-down"
run_installer
ck "退出码非零" test "$RC" -ne 0
ck "输出含 ERROR Moonraker unreachable" grep -qF 'ERROR: afc_stats namespace NOT initialized: Moonraker unreachable' "$CASE/out.log"
ck_not "输出不含 AFC addon installed" grep -qF 'AFC addon installed' "$CASE/out.log"
ck_not "未创建 afc_stats" ns_present afc_stats
ck_not "未创建 lane_data" ns_present lane_data
ck_not "未重启 Klipper" test -s "$CASE/restart.log"

# ---------------------------------------------------------------------------
h "fixture 2f: Moonraker 不可达（首次写 include）-> 非零退出、不假成功"
new_case moonraker-down-install
write_cfg_with_extruder
: > "$CASE/moonraker-down"
run_installer
ck "退出码非零" test "$RC" -ne 0
ck "输出含 ERROR Moonraker unreachable" grep -qF 'ERROR: afc_stats namespace NOT initialized: Moonraker unreachable' "$CASE/out.log"
ck_not "输出不含 AFC addon installed" grep -qF 'AFC addon installed' "$CASE/out.log"
ck "include 已写入（物料阶段完成，但未激活 AFC）" has_include
ck_not "未重启 Klipper" test -s "$CASE/restart.log"

# ---------------------------------------------------------------------------
h "fixture 2g: watcher 在 AFC 清空 namespace 后重建（afc_stats + lane_data）"
new_case ns-watch-recreate
write_cfg_with_extruder
printf '\n[include AFC/*.cfg]\n' >> "$PC"
: > "$CASE/afc-active"
: > "$CASE/ns-afc_stats"
: > "$CASE/ns-lane_data"
rm -f "$CASE/ns-afc_stats" "$CASE/ns-lane_data"
run_watcher_once
ck "watcher 退出码 0" test "$RC" -eq 0
ck "afc_stats 已重建" ns_present afc_stats
ck "lane_data 已重建" ns_present lane_data
ck "重建时未重启 Klipper" test ! -s "$CASE/restart.log"

# ---------------------------------------------------------------------------
h "fixture 2h: watcher 在 Moonraker 不可达时不崩、不假成功"
new_case ns-watch-down
: > "$CASE/moonraker-down"
run_watcher_once
ck "watcher 退出码 0（后台维护尽力而为）" test "$RC" -eq 0
ck_not "未创建 afc_stats" ns_present afc_stats
ck_not "未创建 lane_data" ns_present lane_data

# ---------------------------------------------------------------------------
h "fixture 2i: 真实 Klipper 仓库安装后 git status 干净（AFC extras 进 exclude）"
new_git_case git-install
write_cfg_with_extruder
run_installer
ck "installed_ok" installed_ok "$RC" "$OUT"
ck "git status --porcelain 为空" git_clean
ck "exclude 含 AFC*.py" exclude_has_afc
ck "exclude 含 temperature_oams.py" exclude_has_tmp
ck "exclude 含 managed 标记" grep -qF '# >>> woloong-afc extras' "$KL/.git/info/exclude"
ck "AFC.py 已落位" test -e "$EXTRAS/AFC.py"
ck "temperature_oams.py 已落位" test -e "$EXTRAS/temperature_oams.py"
ck "tracked 用户文件未被动" test -f "$KL/klippy/extras/user_tracked.py"
run_installer
ck "二次安装 rc0" test "$RC" -eq 0
ck "二次安装 status 仍空" git_clean
ck "exclude managed block 只有一处" test "$(grep -cF '# >>> woloong-afc extras' "$KL/.git/info/exclude")" -eq 1

# ---------------------------------------------------------------------------
h "fixture 2j: 修改已跟踪文件仍显示 dirty（exclude 不掩盖 tracked）"
new_git_case git-tracked
write_cfg_with_extruder
run_installer
ck "安装后 status 空" git_clean
printf 'modified by fixture\n' >> "$KL/klippy/extras/user_tracked.py"
ck_not "修改 tracked 后 status 非空" git_clean
ck "status 显示 M klippy/extras/user_tracked.py" bash -c 'git -C "$1" status --porcelain | grep -q "^ M klippy/extras/user_tracked.py"' _ "$KL"
git -C "$KL" checkout -- klippy/extras/user_tracked.py
ck "恢复 tracked 后 status 空" git_clean

# ---------------------------------------------------------------------------
h "fixture 2k: 卸载撤销 exclude、删本包 extras、保留用户文件；不使用 clean -fd"
new_git_case git-uninstall
write_cfg_with_extruder
run_installer
ck "安装后 status 空" git_clean
printf 'user file\n' > "$KL/klippy/extras/user_custom.py"
ck "用户未跟踪文件可见（精确模式）" bash -c 'git -C "$1" status --porcelain | grep -q "^?? klippy/extras/user_custom.py"' _ "$KL"
: > "$CFG/AFC/user-notes.cfg"
run_uninstall
ck "卸载 rc0" test "$RC" -eq 0
ck "exclude 条目已撤销" exclude_clean
ck_not "AFC.py 已删除" test -e "$EXTRAS/AFC.py"
ck_not "temperature_oams.py 已删除" test -e "$EXTRAS/temperature_oams.py"
ck "include 已移除" no_include
ck "用户未跟踪文件仍在" test -f "$KL/klippy/extras/user_custom.py"
ck "tracked 用户文件仍在" test -f "$KL/klippy/extras/user_tracked.py"
ck "config/AFC 保留（用户数据）" test -f "$CFG/AFC/AFC.cfg"
ck "config/AFC 用户文件保留" test -f "$CFG/AFC/user-notes.cfg"
ck "卸载后 status 仅剩用户文件" bash -c '[ "$(git -C "$1" status --porcelain)" = "?? klippy/extras/user_custom.py" ]' _ "$KL"
rm -f "$KL/klippy/extras/user_custom.py"
ck "删除用户文件后 status 空" git_clean

# ---------------------------------------------------------------------------
h "fixture 2l: 用户改过的 AFC.py 卸载时保留；脚本不含 git clean"
ck_not "安装/卸载脚本不含 git clean" grep -qE 'git[[:space:]]+clean' "$INSTALLER"
ck "Uninstall.sh 调用 AFC --uninstall" grep -qF 'woloong-afc-install.sh" --uninstall' "$REPO/scripts/Uninstall.sh"
new_git_case git-uninstall-modified
write_cfg_with_extruder
run_installer
printf '\n# fixture user patch\n' >> "$EXTRAS/AFC.py"
run_uninstall
ck "卸载 rc0（保留用户修改文件不算失败）" test "$RC" -eq 0
ck "用户修改的 AFC.py 保留" test -f "$EXTRAS/AFC.py"
ck "include 已移除（不会 [afc] 无实现）" no_include
ck "exclude 已撤销" exclude_clean
ck "status 显示保留的 AFC.py 为 untracked" bash -c 'git -C "$1" status --porcelain | grep -q "^?? klippy/extras/AFC.py"' _ "$KL"

# ---------------------------------------------------------------------------
h "fixture 2m: 无 [extruder] 也落位 extras -> exclude 仍写、status 空"
new_git_case git-deferred-exclude
write_cfg_no_extruder
run_installer
ck "退出码 0" test "$RC" -eq 0
ck "deferred_ok" deferred_ok "$RC" "$OUT"
ck "git status --porcelain 为空" git_clean
ck "exclude 含 AFC*.py" exclude_has_afc
ck "exclude 含 temperature_oams.py" exclude_has_tmp
ck "include 未启用" no_include

# ---------------------------------------------------------------------------
h "fixture 3: printer.cfg 只读 -> 非零退出、不得假成功"
new_case ro-printer
write_cfg_with_extruder
chmod a-w "$PC"
run_installer
ck "退出码非零" test "$RC" -ne 0
ck "输出含 FAIL" grep -qF 'FAIL' "$CASE/out.log"
ck_not "输出不含 AFC addon installed" grep -qF 'AFC addon installed' "$CASE/out.log"
ck "include 未写入" no_include
chmod u+w "$PC"

# ---------------------------------------------------------------------------
h "fixture 4: cp 失败 -> 非零退出、不得假成功"
new_case cp-failure
write_cfg_with_extruder
make_failing_cp
run_installer
ck "退出码非零" test "$RC" -ne 0
ck "输出含 cp failed" grep -qF 'cp failed' "$CASE/out.log"
ck_not "输出不含 AFC addon installed" grep -qF 'AFC addon installed' "$CASE/out.log"
ck "include 未写入" no_include
ck_not "AFC.py 未落位" test -s "$EXTRAS/AFC.py"

# ---------------------------------------------------------------------------
h "fixture 5: known-bad 旧脚本（cp 失败）必须被抓住"
new_case known-bad-cp
write_cfg_with_extruder
make_failing_cp
cp "$KNOWN_BAD" "$KS/scripts/woloong-afc-install.sh"
run_installer
ck "旧脚本退出码 0（假成功）" test "$RC" -eq 0
ck "旧脚本打印 AFC addon installed" grep -qF 'AFC addon installed' "$CASE/out.log"
ck_not "AFC.py 实际缺失" test -s "$EXTRAS/AFC.py"
if installed_ok "$RC" "$OUT"; then
  bad "known-bad 未被抓住（判据只看日志）"
else
  ok "known-bad 被抓住（判据检查真实文件，不信日志）"
fi

# ---------------------------------------------------------------------------
h "fixture 6: known-bad 旧脚本（printer.cfg 只读）必须被抓住"
new_case known-bad-ro
write_cfg_with_extruder
chmod a-w "$PC"
cp "$KNOWN_BAD" "$KS/scripts/woloong-afc-install.sh"
run_installer
ck "旧脚本退出码 0（假成功）" test "$RC" -eq 0
ck "旧脚本打印 AFC addon installed" grep -qF 'AFC addon installed' "$CASE/out.log"
ck "include 实际未写入" no_include
if installed_ok "$RC" "$OUT"; then
  bad "known-bad 未被抓住（include 缺失仍判成功）"
else
  ok "known-bad 被抓住（判据检查 include）"
fi
chmod u+w "$PC"

# ---------------------------------------------------------------------------
h "fixture 7: service 模板 / 可执行位"
ck "脚本在 git 中为 100755" bash -c "git -C '$REPO' ls-files -s scripts/woloong-afc-install.sh | grep -q '^100755'"
ck "KSC 单元 ExecStartPre 带 '-'" grep -qF 'ExecStartPre=-"KS_DIR/scripts/woloong-afc-install.sh"' "$REPO/scripts/KlipperScreen.service"
ck_not "KSC 单元没有非 '-' 的 ExecStartPre" grep -qE '^ExecStartPre="KS_DIR/scripts/woloong-afc-install.sh"' "$REPO/scripts/KlipperScreen.service"
OS_UNIT="$REPO/../Woloong-OS/pack/assets/systemd/KlipperScreen.service"
if [ -f "$OS_UNIT" ]; then
  ck "OS pack 单元 ExecStartPre 带 '-'" grep -qF 'ExecStartPre=-/home/pi/woloong-klipperScreen/scripts/woloong-afc-install.sh' "$OS_UNIT"
else
  printf '  - SKIP OS pack 单元（未检出同级 Woloong-OS）\n'
fi

# ---------------------------------------------------------------------------
printf '\nAFC_INSTALL_FIXTURES pass=%d fail=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -ne 0 ]; then
  exit 1
fi
exit 0
