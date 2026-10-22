# woloong-release —— 发行树元数据（Woloong-KlipperScreen）

本目录是本发行仓库（Woloong-klipperScreen）的**发行元数据**，不是运行时组件。

## 模型（D20：自有发行树）

仓库 `main` 分支 = **官方 KlipperScreen + woloong 定制**的合并体，即设备上直接可用的部署形态：

- `styles/woloong/**` —— woloong 主题（112 文件，新目录）
- `panels/splash_screen.py` —— 定制启动画面（**替换官方受控文件**）
- `KlipperScreen-Theme-Woloong/` —— 定制的原始资产与安装脚本（deploy.sh / R_deploy.sh）

**版本控制与跟踪的对象是本仓库，而非上游官方仓库。** 上游数据只是输入。

## 目录

| 路径 | 作用 |
| --- | --- |
| `assets.manifest.json` | 全部定制文件的逐项 SHA256 清单（校验与重放依据） |
| `baseline/splash_screen.py` | 上游官方原始文件（打补丁的基线） |
| `patches/splash_screen.patch` | 相对基线的定制补丁（130 行 / 4 hunks） |
| `tools/make-patch.sh` | 由基线 + 当前文件重新生成补丁 |
| `tools/verify-assets.sh` | 按清单校验当前工作区定制文件是否完整 |

## 吸收上游更新（重新叠加，不做 merge）

1. `git fetch upstream --tags`
2. 用上游树整体替换工作区（保留 `.git/` 与 `woloong-release/`）
3. 应用定制：`cp -r` 主题到 `styles/woloong/`；`git apply woloong-release/patches/splash_screen.patch`
4. **校验**：`tools/verify-assets.sh` 必须全绿；补丁必须干净应用（上游若改动基线文件 → 失败即停，人工复核）
5. 提交两个 commit：`upstream: KlipperScreen @ <sha>` + `woloong: re-apply customization`
6. 打 tag `woloong-<上游短 sha>-<n>` 并推送

## 发布产物（Release 资产）

版本号 = **上游发布版本号**（例如上游 `v0.4.7` → 我们的 tag / Release / 资产文件名都用 `v0.4.7`），不做二次编号。

| 资产 | 说明 |
| --- | --- |
| `Woloong-KlipperScreen-<tag>.tar.gz` | 发行树源码包（上游 + woloong 定制，重叠加后门禁通过） |
| `Woloong-KlipperScreen-<tag>.zip` | 同上，zip 格式 |
| `SHA256SUMS.txt` | 两个包的 SHA256，供设备端校验 |

发布流程见 `.github/workflows/upstream-sync.yml`：重叠加 → `verify-assets` 门禁 → 推 main 与 tag → 打包 → `gh release create`（资产随 tag 发布）→ 通知 Woloong-OS（携带资产名与 sha256）。

## 设备端（唯一更新入口，D17）

`woloong-addon update klipperscreen` —— 取我们的发行包覆盖安装路径，再校验定制在位并重启服务。
