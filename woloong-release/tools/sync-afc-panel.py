#!/usr/bin/env python3
"""按 VENDOR.md 的 pin 重新同步 AFC 面板（上游 ArmoredTurtle/AFC-Klipper-Screen-Add-On）。

用法：
    python3 woloong-release/tools/sync-afc-panel.py            # 重放当前 pin（默认，幂等）
    python3 woloong-release/tools/sync-afc-panel.py --latest   # 先取上游 main head 作为新 pin
    python3 woloong-release/tools/sync-afc-panel.py --pin <sha>

流程：下载 pin 的 tar.gz → 更新 baseline/panels/AFC.py → 重放 patches/panels_AFC.py.patch
      → 覆盖 afc_icons/ 与 config/AFC_menu.conf → 重新生成补丁 → 更新清单与 VENDOR.md → 校验。
补丁冲突（上游改了同一区域）时**停止**，保留现场，人工重锚定。
"""
import hashlib
import shutil
import io
import json
import re
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from datetime import date, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAN = ROOT / "woloong-release"
VENDOR = ROOT / "VENDOR.md"
PATCH = MAN / "patches" / "panels_AFC.py.patch"
UP = "ArmoredTurtle/AFC-Klipper-Screen-Add-On"

FILES = {
    "panels/AFC.py": "KlipperScreen/AFC.py",
    "config/AFC_menu.conf": "KlipperScreen/AFC_menu.conf",
    "afc_icons/AFC.svg": "KlipperScreen/afc_icons/AFC.svg",
    "afc_icons/FilamentReelIcon.svg": "KlipperScreen/afc_icons/FilamentReelIcon.svg",
    "afc_icons/HTLF.svg": "KlipperScreen/afc_icons/HTLF.svg",
    "afc_icons/Night_Owl.svg": "KlipperScreen/afc_icons/Night_Owl.svg",
    "afc_icons/box_turtle_colored_logo.svg": "KlipperScreen/afc_icons/box_turtle_colored_logo.svg",
}
KINDS = {"panels/AFC.py": "tracked-file-replaced"}


def die(msg: str) -> "NoReturn":
    print("[FAIL] " + msg, file=sys.stderr)
    sys.exit(1)


def bash_exe() -> str:
    b = shutil.which("bash")
    if b:
        return b
    for c in (r"C:\Program Files\Git\bin\bash.exe", "/bin/bash", "/usr/bin/bash"):
        if Path(c).exists():
            return c
    die("找不到 bash（生成补丁与校验需要）")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_pin() -> str:
    m = re.search(r"^\| pin \| \x60([0-9a-f]{40})\x60 \|", VENDOR.read_text(encoding="utf-8"), re.M)
    if not m:
        die("VENDOR.md 里找不到 pin")
    return m.group(1)


def upstream_head() -> str:
    out = subprocess.run(["git", "ls-remote", f"https://github.com/{UP}.git", "refs/heads/main"],
                         capture_output=True, text=True, check=True).stdout
    return out.split()[0]


def fetch(pin: str, dest: Path) -> None:
    url = f"https://codeload.github.com/{UP}/tar.gz/{pin}"
    print(f"  下载 {url}")
    with urllib.request.urlopen(url, timeout=120) as r, tempfile.NamedTemporaryFile(delete=False, suffix=".tgz") as f:
        f.write(r.read())
        tmp = Path(f.name)
    try:
        with tarfile.open(tmp, "r:gz") as tar:
            for member in tar.getmembers():
                rel = member.name.split("/", 1)[-1]
                if rel in FILES.values() and member.isfile():
                    data = tar.extractfile(member).read()
                    (dest / rel.replace("/", "__")).write_bytes(data)
    finally:
        tmp.unlink(missing_ok=True)


def apply_patch() -> None:
    r = subprocess.run(["git", "apply", "--recount", str(PATCH)], cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        die("补丁应用失败（上游可能改了同一区域）——请人工重锚定：\n" + (r.stderr or r.stdout))


def update_manifest() -> None:
    tsv_path = MAN / "assets.manifest.tsv"
    rows = [l for l in tsv_path.read_text(encoding="utf-8").splitlines() if l.strip()]
    rows = [l for l in rows if l.split("\t")[-1] not in FILES]
    for rel in FILES:
        rows.append(f"{sha256(ROOT / rel)}\t{rel}")
    tsv_path.write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")

    jpath = MAN / "assets.manifest.json"
    doc = json.loads(jpath.read_text(encoding="utf-8"))
    doc["entries"] = [e for e in doc["entries"] if e.get("path") not in FILES]
    for rel in FILES:
        p = ROOT / rel
        doc["entries"].append({"path": rel, "sha256": sha256(p), "bytes": p.stat().st_size,
                               "kind": KINDS.get(rel, "vendored-file")})
    jpath.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def update_vendor(pin: str) -> None:
    text = VENDOR.read_text(encoding="utf-8")
    text = re.sub(r"^\| pin \| \x60[0-9a-f]{40}\x60 \|", f"| pin | \x60{pin}\x60 |", text, flags=re.M)
    text = re.sub(r"^\| 同步日期 \| .* \|", f"| 同步日期 | {date.today().isoformat()} |", text, flags=re.M)
    desc = {
        "panels/AFC.py": "基线（上游原版），实际文件由 patch 生成",
        "config/AFC_menu.conf": "菜单定义（含 [menu __main AFC_status]）",
        "afc_icons/AFC.svg": "菜单图标",
        "afc_icons/FilamentReelIcon.svg": "料盘图标（代码硬依赖）",
        "afc_icons/HTLF.svg": "HTLF 图标",
        "afc_icons/Night_Owl.svg": "Night Owl 图标",
        "afc_icons/box_turtle_colored_logo.svg": "BoxTurtle 图标",
    }
    rows = []
    for rel, up in FILES.items():
        src = MAN / "baseline" / rel if rel == "panels/AFC.py" else ROOT / rel
        rows.append(f"| \x60{rel}\x60 | \x60{up}\x60 | \x60{sha256(src)}\x60 | {desc.get(rel, '')} |")
    block = "\n".join(rows)
    text = re.sub(r"(?ms)^\| \x60panels/AFC\.py\x60.*?(?=\n\n)", block, text, count=1)
    VENDOR.write_text(text, encoding="utf-8", newline="\n")


def main() -> None:
    args = sys.argv[1:]
    pin = None
    if "--pin" in args:
        pin = args[args.index("--pin") + 1]
    elif "--latest" in args:
        pin = upstream_head()
        print(f"上游 main head: {pin}")
    if pin is None:
        pin = read_pin()
    pin = pin.strip()
    if not re.fullmatch(r"[0-9a-f]{40}", pin):
        die(f"pin 非法：{pin}")

    print(f"== sync-afc-panel ==\n  pin: {pin}")
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        fetch(pin, tmp)
        baseline = MAN / "baseline" / "panels" / "AFC.py"
        baseline.parent.mkdir(parents=True, exist_ok=True)
        # 1) 新上游原文 → baseline 与 panels（先当基线用，便于重放补丁）
        up_afc = (tmp / "KlipperScreen__AFC.py").read_bytes()
        baseline.write_bytes(up_afc)
        (ROOT / "panels/AFC.py").write_bytes(up_afc)
        # 2) 重放本地补丁
        if PATCH.exists():
            apply_patch()
        # 3) 其余文件直接覆盖
        for rel, up in FILES.items():
            if rel == "panels/AFC.py":
                continue
            (ROOT / rel).parent.mkdir(parents=True, exist_ok=True)
            (ROOT / rel).write_bytes((tmp / up.replace("/", "__")).read_bytes())
    # 4) 重新生成补丁（基线 vs 当前）
    subprocess.run([bash_exe(), str(MAN / "tools/make-patch.sh")], cwd=ROOT, check=True)
    # 5) 清单与 VENDOR
    update_manifest()
    update_vendor(pin)
    # 6) 校验
    r = subprocess.run([bash_exe(), str(MAN / "tools/verify-assets.sh")], cwd=ROOT)
    if r.returncode != 0:
        die("同步后 verify-assets 未通过")
    print("[OK] 完成：baseline/patch/清单/VENDOR 已更新")


if __name__ == "__main__":
    main()
