# 版本与 tag 规则（Woloong-KlipperScreen）

## 基准

- 版本号的**主前缀 = 上游 KlipperScreen 的 tag**（当前 `v0.4.7`，见 `woloong-release/upstream.json` 的 `base_ref`）。
- 本仓库**不得自行新增上游号**（例如上游没有 v0.4.8，就不能打 v0.4.8 / v0.4.9）。

## 定制 tag 形式

```
v<上游版本>-<定制标识><序号>
```

| 标识 | 用途 |
|---|---|
| `ws` | websocket / 核心通信修复 |
| `afc` | AFC 面板集成 |
| `theme` | 主题 / 图标 / 配色 |
| `ui` | 界面布局 / 可用性修复 |

示例：

| tag | 含义 |
|---|---|
| `v0.4.7` | 纯上游基线（c5fcc279） |
| `v0.4.7-ws1` | 基于 v0.4.7 的第 1 次 ws 定制（空 api_key 不再 identify/token） |
| `v0.4.7-afc1` | 基于 v0.4.7 的第 1 次 AFC 集成（AFC add-on @ bd6adb6） |

## 上游升版时

1. 以新上游 tag 为基线重叠加；
2. 序号从 1 重新开始（如 `v0.4.8-ws1`）；
3. `woloong-release/upstream.json` 的 `base_ref` / `base_sha` 同步更新。

## 约束（门禁）

- tag 必须匹配 `^v<base_ref>-(ws|afc|theme|ui)[0-9]+$`，或等于 `base_ref` 本身；
- Woloong-OS 清单的 `klipperscreen.pin_ref` 必须等于最新定制 tag，且该 tag 指向 `pin` 提交；
- AFC add-on 无上游 tag，其来源 commit 记录在 `VENDOR.md`（集成后新增）。
