#!/bin/bash
# ============================================================================
# 夹具：woloong-afc-install.sh（AFC 首启落位 / fail-fast）
#
# 覆盖：
#   1) 无 [extruder]：物料落位，include 必须关闭（且不打印 installed）
#   2) 有 [extruder]：四项校验全绿 + Klipper reload；二次执行幂等
#   3) printer.cfg 只读：非零退出，不打印 installed
#   4) cp 失败：非零退出，不打印 installed，include 不落
#   5) known-bad（1627 旧脚本）cp 失败：必须被「成功后四项校验」判据抓住
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

CASE=""; KS=""; H=""; BIN=""; CFG=""; EXTRAS=""; PC=""

new_case() {
  CASE="$TMPROOT/$1"
  KS="$CASE/ks"
  H="$CASE/home"
  BIN="$CASE/bin"
  rm -rf "$CASE"
  mkdir -p "$KS/scripts" "$H/printer_data/config" "$H/klipper/klippy/extras" "$BIN"
  cp "$INSTALLER" "$KS/scripts/woloong-afc-install.sh"
  chmod +x "$KS/scripts/woloong-afc-install.sh"
  cp -R "$REPO/afc" "$KS/afc"
  CFG="$H/printer_data/config"
  EXTRAS="$H/klipper/klippy/extras"
  PC="$CFG/printer.cfg"
  # 默认 curl 桩：不发网络请求
  cat > "$BIN/curl" <<'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$BIN/curl"
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
  OUT="$(HOME="$H" PATH="$BIN:$PATH" bash "$KS/scripts/woloong-afc-install.sh" 2>&1)"
  RC=$?
  printf '%s\n' "$OUT" > "$CASE/out.log"
}

make_fake_curl_smart() {
  cat > "$BIN/curl" <<EOF
#!/bin/sh
case "\$*" in
  *machine/services/restart*)
    echo x >> "$CASE/restart.log"
    : > "$CASE/afc-active"
    exit 0 ;;
  *objects/query*configfile*)
    if [ -f "$CASE/afc-active" ]; then
      printf '%s\n' '{"result":{"status":{"configfile":{"config":{"afc":{}}}}}}}'
    else
      printf '%s\n' '{"result":{"status":{"configfile":{"config":{}}}}}'
    fi
    exit 0 ;;
  *print_stats*)
    printf '%s\n' '{"result":{"status":{"print_stats":{"state":"ready"}}}}'
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

make_fake_curl_printing() {
  cat > "$BIN/curl" <<EOF
#!/bin/sh
case "\$*" in
  *machine/services/restart*)
    echo x >> "$CASE/restart.log"
    : > "$CASE/afc-active"
    exit 0 ;;
  *objects/query*configfile*)
    if [ -f "$CASE/afc-active" ]; then
      printf '%s\n' '{"result":{"status":{"configfile":{"config":{"afc":{}}}}}}}'
    else
      printf '%s\n' '{"result":{"status":{"configfile":{"config":{}}}}}'
    fi
    exit 0 ;;
  *print_stats*)
    printf '%s\n' '{"result":{"status":{"print_stats":{"state":"printing"}}}}'
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

# 「成功后四项校验」判据：日志只说成功不算，必须文件真的在
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
  return 0
}

# ---------------------------------------------------------------------------
h "fixture 1: 无 [extruder] -> 物料落位、include 关闭"
new_case no-extruder
write_cfg_no_extruder
run_installer
ck "退出码 0" test "$RC" -eq 0
ck "deferred_ok（物料在 + include 关闭 + 不打印 installed）" deferred_ok "$RC" "$OUT"
ck "AFC.py 已落位" test -s "$EXTRAS/AFC.py"
ck "AFC.cfg 已落位" test -s "$CFG/AFC/AFC.cfg"
ck "AFC.var.unit 已生成" test -s "$CFG/AFC/AFC.var.unit"
ck "include 未启用" no_include
ck "输出说明按钮仍隐藏" grep -qF 'menu button stays hidden' "$CASE/out.log"
ck "输出给出重新触发动作（Web 服务面板重启 KSC）" grep -qF 'KlipperScreen service' "$CASE/out.log"
printf '\n[include AFC/*.cfg]\n' >> "$PC"
run_installer
ck "遗留 include 在无 [extruder] 时被关闭（退出码 0）" test "$RC" -eq 0
ck "遗留 include 已移除" no_include
ck "输出说明已移除 include" grep -qF 'removed [include AFC/*.cfg]' "$CASE/out.log"

# ---------------------------------------------------------------------------
h "fixture 2: 有 [extruder] -> 四项校验全绿 + Klipper reload + 幂等"
new_case with-extruder
write_cfg_with_extruder
make_fake_curl_smart
run_installer
ck "installed_ok（rc0 + installed + 四项）" installed_ok "$RC" "$OUT"
ck "输出含 4/4" grep -qF '4/4' "$CASE/out.log"
ck "已请求 Moonraker 重启 Klipper" test -s "$CASE/restart.log"
ck "等待到 [afc] active" grep -qF '[afc] section active' "$CASE/out.log"
ck "include 已写入一行" test "$(grep -cF '[include AFC/*.cfg]' "$PC")" -eq 1
run_installer
ck "第二次退出码 0" test "$RC" -eq 0
ck "第二次未再重启 Klipper" test "$(wc -l < "$CASE/restart.log")" -eq 1
ck "include 仍只有一行（幂等）" test "$(grep -cF '[include AFC/*.cfg]' "$PC")" -eq 1

# ---------------------------------------------------------------------------
h "fixture 2b: 打印中不重启 Klipper（保护打印）"
new_case printing-guard
write_cfg_with_extruder
make_fake_curl_printing
run_installer
ck "退出码 0（include 照常写入）" test "$RC" -eq 0
ck "installed_ok" installed_ok "$RC" "$OUT"
ck_not "未请求重启 Klipper" test -s "$CASE/restart.log"
ck "输出说明正在打印、跳过 reload" grep -qF 'skip Klipper reload' "$CASE/out.log"

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
