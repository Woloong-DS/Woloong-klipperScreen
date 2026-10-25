# AFC 面板来源（vendor）

本文件记录 AFC 面板的上游来源、固定版本与本地改动。**同步脚本读写本文件**，请勿手工改动表格格式。

| 项 | 值 |
| --- | --- |
| 上游仓库 | `ArmoredTurtle/AFC-Klipper-Screen-Add-On` |
| 许可 | GPL-3.0（与 AGPL-3.0 兼容；保留上游版权声明） |
| pin | `bd6adb6d0707e8d3c4095ba178221162d7a055bc` |
| 上游日期 | 2026-09-05 |
| 同步日期 | 2026-10-25 |
| 同步命令 | `python3 woloong-release/tools/sync-afc-panel.py` |
| 落后审计 | `bash woloong-release/tools/check-afc-upstream.sh` |

## 文件清单（sha256 为**上游原版**）

| 本仓库路径 | 上游路径 | sha256（上游） | 说明 |
| --- | --- | --- | --- |
| `panels/AFC.py` | `KlipperScreen/AFC.py` | `a81dc6c3215d664a6f54d7de994e3b455125ec3c432410a5e683c1016b2778db` | 基线（上游原版），实际文件由 patch 生成 |
| `config/AFC_menu.conf` | `KlipperScreen/AFC_menu.conf` | `1ad8ab5f56a78ca5b6c6c0581e973f7c3978a2dbe32107370c001e5c90ce277b` | 菜单定义（含 [menu __main AFC_status]） |
| `afc_icons/AFC.svg` | `KlipperScreen/afc_icons/AFC.svg` | `297ca1ddf36747e1e8976991639a06fe1e47b543505757c41f5017651f8fce75` | 菜单图标 |
| `afc_icons/FilamentReelIcon.svg` | `KlipperScreen/afc_icons/FilamentReelIcon.svg` | `2c76978815af0ae7486c383b20f1586a1623f45cd974e0e74472ab7de328a73a` | 料盘图标（代码硬依赖） |
| `afc_icons/HTLF.svg` | `KlipperScreen/afc_icons/HTLF.svg` | `63c6b08089ef1878252b94619d2b5a066a0160910fff78f87d3c51b22b845abd` | HTLF 图标 |
| `afc_icons/Night_Owl.svg` | `KlipperScreen/afc_icons/Night_Owl.svg` | `b8b54d582dd3d96e1488aefa4a7952c40543b699d8fc6b4fcc17121b6bc2fab0` | Night Owl 图标 |
| `afc_icons/box_turtle_colored_logo.svg` | `KlipperScreen/afc_icons/box_turtle_colored_logo.svg` | `f3f489456626b469f209b62c25be30a92c154b1add2e8808cbb36ec2938858bb` | BoxTurtle 图标 |

## 本地改动（全部在 `panels/AFC.py`，由 `patches/panels_AFC.py.patch` 重放）

1. **修正上游拼写错误**：`extract_afc_data()` 中 `result.get("status:", {})` → `result.get("status", {})`。
   不修则 `printer.afc.status` 的返回永远解析为空，面板无法构建。
2. **无硬件守卫**：`load_object_list()` 中若对象列表没有 `AFC`（含 `AFC_*`），记录 info 并退回主菜单；
   避免配置残留时出现空面板或错误弹窗。

> 主题适配（图标配色、9 处硬编码颜色）属于阶段 2，不在本文件记录范围；届时同样走 patch。
