<p align="center">
  <img src="styles/woloong/Woloong_Logo.png" alt="Woloong" height="120">
</p>

<h1 align="center">Woloong-KlipperScreen</h1>

<p align="center">
  <b>官方 KlipperScreen + Woloong 定制</b><br>
  面向 Klipper 的触摸屏界面 · 内置 Woloong 主题与启动画面 · 随上游版本滚动更新
</p>

<p align="center">
  <a href="https://github.com/Woloong-DS/Woloong-klipperScreen/releases">Releases</a> ·
  <a href="woloong-release/README.md">定制说明</a> ·
  <a href="https://github.com/KlipperScreen/KlipperScreen">上游仓库</a> ·
  <a href="https://klipperscreen.readthedocs.io/">上游文档</a>
</p>

---

## 这是什么

本仓库是 [KlipperScreen/KlipperScreen](https://github.com/KlipperScreen/KlipperScreen) 的**自有发行树**：

> `main` = 官方 KlipperScreen（当前基线 v0.4.7） + Woloong 定制

KlipperScreen 是 Python 应用，**源码即产物**，不需要构建；因此本仓库直接以 **Release 源码包** 的形式发布，
供 Woloong-OS 镜像与设备端更新器取用。本仓库只做「吸收上游 → 重放定制 → 门禁 → 打包 → 发布」，不向上游提交 PR。

| 项目 | 说明 |
| --- | --- |
| 上游 | `KlipperScreen/KlipperScreen`（AGPL-3.0，版权归上游作者） |
| 定制清单 | [`woloong-release/assets.manifest.tsv`](woloong-release/assets.manifest.tsv)（逐文件 SHA256） |
| 当前基线 | [`woloong-release/upstream.json`](woloong-release/upstream.json) 的 `base_ref` |
| 发布产物 | `Woloong-KlipperScreen-<tag>.tar.gz` / `.zip` + `SHA256SUMS.txt` |

---

## 版本与发布规则

版本号**直接采用上游发布版本**，不二次编号，便于一一对照。

| 对象 | 规则 | 示例 |
| --- | --- | --- |
| git tag | 与上游 tag 同名 | `v0.4.7` |
| Release 标题 | `Woloong-KlipperScreen <tag>` | `Woloong-KlipperScreen v0.4.7` |
| Release 资产 | `Woloong-KlipperScreen-<tag>.tar.gz` / `.zip` + `SHA256SUMS.txt` | `Woloong-KlipperScreen-v0.4.7.tar.gz` |

> 与上游**同名 tag** 意味着 `git fetch --tags --force` 会把本地 tag 指到上游提交；
> 发布流程会用 `git tag -f` 把它重指到我们的发行提交再强推，所以**始终以 Releases 页里该 tag 指向的提交为准**。
> 上游发布 v0.4.8 时，本仓库自动产出 `v0.4.8` 与对应资产。

**当前发行：见 [Releases](https://github.com/Woloong-DS/Woloong-klipperScreen/releases)。**

---

## 安装 / 更新

### A. 交给 Woloong-OS 更新管理器（推荐）

设备端由 Woloong-OS 统一管理：

```bash
woloong-addon update klipperscreen
```

对应 Moonraker 的更新段（安装路径以设备为准）：

```ini
[update_manager Woloong-klipperScreen]
type: git_repo
path: ~/woloong-klipperScreen
origin: https://github.com/Woloong-DS/Woloong-klipperScreen.git
managed_services: KlipperScreen
```

### B. 手动更新（脚本）

```bash
tag=$(curl -fsSL https://api.github.com/repos/Woloong-DS/Woloong-klipperScreen/releases/latest | jq -r .tag_name)
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/$tag.tar.gz" \
  "https://github.com/Woloong-DS/Woloong-klipperScreen/releases/download/$tag/Woloong-KlipperScreen-$tag.tar.gz"
tar -xzf "$tmp/$tag.tar.gz" -C ~/woloong-klipperScreen --strip-components=1
rm -rf "$tmp"
sudo systemctl restart KlipperScreen
echo "已更新到 $tag"
```

### C. 随镜像预装

Woloong-OS 镜像已内置本界面（`~/woloong-klipperScreen`，服务名 `KlipperScreen`），
烧录后无需手动安装，后续更新走 A 或 B。

---

## 上游同步与发布（自动化）

由 [`.github/workflows/upstream-sync.yml`](.github/workflows/upstream-sync.yml) 承担，每周一 `03:17 UTC` 定时审计，也可手动触发。

```
上游版本审计 ──┬─ 无新版 ──────────────────────────────→ 结束（零产出）
               └─ 有新版 ──→ 重叠加 → 门禁 → 推送 main/tag → 打包 → 发布 → 通知下游
```

- **重叠加**：上游整树替换 → 重放定制（补丁 + 清单文件）→ 应用 `remove.list` → 更新基线声明；
  结果与当前树完全一致时**不产生任何提交、不移动 tag**（幂等）。
- **门禁**：`verify-assets` 全量校验定制文件 SHA256，并断言 `remove.list` 中的文件确实不存在，任一不过即拒绝发布。
- **漂移保护**：上游若改动了被打补丁的受控文件，流程会**停下来**并要求人工重锚定
  （更新 `woloong-release/baseline/` → 重新生成补丁 → 更新清单哈希），不会带着错补丁发布。
- **通知下游**：发布成功后以 `repository_dispatch`（事件 `component-released`）通知
  Woloong-OS 更新适配层（`pin` / `pin_ref` / 资产名）。
- **补发 / 重发**：`release-assets` 工作流可对指定版本重新打包并上传资产（必要时移动 tag），同样会通知下游。

---

## 定制内容

受控文件（打补丁或自有文案）与新增文件共 114 项，逐项记录在
[`woloong-release/assets.manifest.tsv`](woloong-release/assets.manifest.tsv)：

| 类别 | 路径 |
| --- | --- |
| 受控文件（打补丁） | `panels/splash_screen.py`（启动画面） |
| 自有文案 | `README.md`（本文件，重叠加时保留） |
| 新增主题 | `styles/woloong/`（主题样式、图标与品牌资源，112 个文件） |
| 上游 CI 精简 | `.github/`（按 `woloong-release/remove.list` 移除上游 codeql/docs/test 等工作流与 dependabot） |
| 发行元数据 | `woloong-release/`（基线、补丁、清单、`upstream.json`、工具脚本） |

定制细节与风险说明见 [`woloong-release/README.md`](woloong-release/README.md)。

---

## 仓库结构

| 路径 | 作用 |
| --- | --- |
| `screen.py`、`panels/`、`ks_includes/` | KlipperScreen 主程序与面板（上游 + 定制） |
| `styles/` | 上游主题与 `woloong` 主题（定制） |
| `config/`、`scripts/`、`docs/` | 示例配置、安装/启动脚本、上游文档 |
| `woloong-release/` | 发行元数据：基线、补丁、清单、`upstream.json`、工具脚本 |
| `.github/workflows/` | `upstream-sync`（审计/重叠加/门禁/发布）、`release-assets`（补发）、`keepalive` |

---

## 本地开发与调试

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r scripts/KlipperScreen-requirements.txt
# 依赖、显示与 systemd 配置详见 docs/Installation.md
```

调试主题时，在 `KlipperScreen.conf` 中设置 `theme = woloong` 后启动界面即可。
提交前请保证 **LF** 换行（`.gitattributes` 已强制），并在改动定制文件后更新清单（见下）。

---

## 发布产物形态

`Woloong-KlipperScreen-v0.4.7.tar.gz` 解压后即为可直接部署的完整发行树（不含 `.git`）：

```
screen.py  panels/  ks_includes/  config/  scripts/  docs/
styles/woloong/            # 主题（含 Woloong_Logo.png）
woloong-release/           # 发行元数据（清单/基线/补丁/工具）
```

---

## 维护者须知

- **改动任何定制文件后**，必须同步更新 `woloong-release/assets.manifest.tsv`（与 `.json`）中的
  `sha256` / `bytes`，否则 CI 的「定制资产完整性」门禁会失败：
  ```bash
  bash woloong-release/tools/verify-assets.sh    # 本地自检
  ```
- **修改本 README 也一样**（它本身是受清单保护的定制文件）。
- 手动重叠加：`bash woloong-release/tools/fork-sync.sh . --upstream-ref <上游 tag> --tag <上游 tag>`。
- 审计上游是否落后：`bash woloong-release/tools/check-upstream.sh`。

---

## 许可与致谢

本项目遵循上游 **AGPL-3.0** 许可，KlipperScreen 的版权归 [KlipperScreen](https://github.com/KlipperScreen/KlipperScreen) 作者及其贡献者所有。
Woloong 定制部分由 [Woloong-DS](https://github.com/Woloong-DS) 维护。
