# Woloong-KlipperScreen

**Woloong 定制版 KlipperScreen** —— 面向 Woloong 品牌 3D 打印机的触摸屏界面发行树。

本仓库 = [上游 KlipperScreen](https://github.com/KlipperScreen/KlipperScreen) + Woloong 定制，按「重叠加」方式跟随上游发布：
**不做 merge**，每个上游版本都用上游树整体替换后重放定制，定制是否完整由门禁逐文件校验。

- 发行版本号与上游发布**一一对应**（上游 `v0.4.7` → 本仓库 `v0.4.7`）
- 发行资产：`Woloong-KlipperScreen-<tag>.tar.gz` / `.zip` + `SHA256SUMS.txt`
- 许可：AGPL-3.0（继承上游）

## 与上游的差异

| 内容 | 路径 | 说明 |
| --- | --- | --- |
| Woloong 主题 | `styles/woloong/` | 品牌配色、图标与布局资源（112 个文件，上游没有的新目录） |
| 启动画面 | `panels/splash_screen.py` | 在上游原文件上打补丁，补丁见 `woloong-release/patches/` |
| 上游 CI 精简 | `.github/` | 按 `woloong-release/remove.list` 移除上游 codeql/docs/test 等工作流与 dependabot |
| 发行元数据 | `woloong-release/` | 定制清单、基线、补丁、重叠加与校验工具 |

除上述内容外，代码与上游保持一致。

## 获取与安装

**发行包（推荐）**

```bash
# 以 v0.4.7 为例
curl -LO https://github.com/Woloong-DS/Woloong-klipperScreen/releases/download/v0.4.7/Woloong-KlipperScreen-v0.4.7.tar.gz
curl -LO https://github.com/Woloong-DS/Woloong-klipperScreen/releases/download/v0.4.7/SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt
```

设备端由 **Woloong-OS** 的更新管理器统一安装与更新（`woloong-addon update klipperscreen`），一般无需手工操作。

**从源码部署**

```bash
git clone --branch v0.4.7 https://github.com/Woloong-DS/Woloong-klipperScreen.git
cd Woloong-KlipperScreen
# 依赖安装、KlipperScreen.conf 与 systemd 配置见上游文档：docs/Installation.md
```

## 版本与发布

- tag、Release 标题、资产文件名都使用**上游发布版本号**，不额外编号
- 每个 Release 附带两个源码包（tar.gz / zip）与 `SHA256SUMS.txt`
- 发布记录：<https://github.com/Woloong-DS/Woloong-klipperScreen/releases>

## 跟随上游更新（维护者）

自动（默认）：每周一 `03:17 UTC` 巡检上游 tag；发现新版本后依次执行
**重叠加 → 门禁 → 推送 main 与 tag → 打包 → 发布 Release → 通知 Woloong-OS**。

手动：Actions → **upstream-sync** → Run workflow（可填 `upstream_ref`、`next_tag`、`do_push`）。

本地重叠加与预检：

```bash
bash woloong-release/tools/fork-sync.sh . --upstream-ref v0.4.8 --dry-run   # 只检查，不改动
bash woloong-release/tools/fork-sync.sh . --upstream-ref v0.4.8 --tag v0.4.8
```

发布前门禁（定制资产完整性 + 移除清单断言）：

```bash
bash woloong-release/tools/verify-assets.sh
```

重叠加的原理、目录约定与补丁流程见 [`woloong-release/README.md`](woloong-release/README.md)。

## 目录结构

```
.
├── screen.py, panels/, ks_includes/, config/, styles/   # 上游 KlipperScreen
├── styles/woloong/                                      # Woloong 主题（定制）
├── panels/splash_screen.py                              # 启动画面（定制补丁）
├── woloong-release/                                     # 发行元数据与工具
│   ├── assets.manifest.{tsv,json}                       # 定制文件清单（SHA256）
│   ├── baseline/  patches/                              # 受控文件基线与补丁
│   ├── tools/                                           # fork-sync / verify-assets / check-upstream
│   └── upstream.json                                    # 已吸收的上游基线
└── docs/                                                # 上游文档
```

## 问题反馈

- 定制、发行、打包相关问题：本仓库 [Issues](https://github.com/Woloong-DS/Woloong-klipperScreen/issues)
- 上游功能与通用安装问题：<https://github.com/KlipperScreen/KlipperScreen/issues>，文档 <https://klipperscreen.readthedocs.io/>

## 许可

[AGPL-3.0](LICENSE)。上游代码版权归 KlipperScreen 作者所有；Woloong 定制部分同样以 AGPL-3.0 发布。

---

<sub>本 README 由本仓库维护，重叠加（fork-sync）时会保留，不会被上游 README 覆盖。</sub>
