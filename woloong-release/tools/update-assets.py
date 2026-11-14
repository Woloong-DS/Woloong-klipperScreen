#!/usr/bin/env python3
"""重算 KSC assets.manifest，并把 afc/ 下新增文件加入清单。"""
import argparse, hashlib, json
from pathlib import Path
ap=argparse.ArgumentParser(); ap.add_argument("--root",required=True); a=ap.parse_args()
root=Path(a.root); man=root/"woloong-release"; jp=man/"assets.manifest.json"; tp=man/"assets.manifest.tsv"
data=json.loads(jp.read_text(encoding="utf-8")); entries={e["path"]:e for e in data["entries"] if "__pycache__" not in e["path"].split("/")}
for p in sorted((root/"afc").rglob("*")):
    if not p.is_file(): continue
    if "__pycache__" in p.parts: continue
    rel=p.relative_to(root).as_posix()
    entries.setdefault(rel,{"path":rel,"kind":"vendored-file"})
for rel,e in entries.items():
    p=root/rel
    if not p.is_file():
        continue
    b=p.read_bytes(); e["sha256"]=hashlib.sha256(b).hexdigest(); e["bytes"]=len(b)
data["entries"]=sorted(entries.values(), key=lambda x:x["path"])
jp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
tp.write_text("".join("%s\t%s\n" % (e["sha256"],e["path"]) for e in data["entries"]),encoding="utf-8")
print("ASSETS_UPDATED",len(data["entries"]))
