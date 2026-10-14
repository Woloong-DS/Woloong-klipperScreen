# Woloong Theme for KlipperScreen

专为 **Woloong** 品牌 3D 打印机设计的 KlipperScreen 主题，融合 DIY 创客文化与工业精密美学。

---

## 品牌视觉基因

| 元素 | 设计特征 | 含义 |
|------|---------|------|
| 主色 | 纯红 `#FF0000` | 力量、精密制造、工业警示 |
| 背景 | 深空黑 `#0a0a0f` | 专业设备、沉浸式深色界面 |
| 几何 | 六边形蜂巢 | 模块化结构、机械精度 |
| 面板 | 工业岩板灰 `#13131a` | 立体层次、CNC 加工质感 |

---

## 快速安装

将本目录复制到设备上，执行安装脚本：

```bash
cd ~/KlipperScreen-Theme-Woloong
bash deploy.sh
```

脚本会自动完成：
1. 探测 KlipperScreen 安装路径（`~/KlipperScreen`、`/home/pi/KlipperScreen` 等）
2. 部署 `styles/woloong/` 主题文件
3. 部署品牌启动画面 `panels/splash_screen.py`
4. 修改 `KlipperScreen.conf`，添加 `theme = woloong`
5. 自动重启服务（可选）

**指定非标准路径：**
```bash
bash deploy.sh --path /custom/path/to/KlipperScreen
```

---

## 卸载恢复

```bash
cd ~/KlipperScreen-Theme-Woloong
bash R_deploy.sh
```

卸载脚本会自动：
- 删除 `styles/woloong/` 目录
- 恢复原始 `KlipperScreen.conf`（从 deploy 备份）
- 恢复原始 `splash_screen.py`（从 deploy 备份）
- 可选重启服务

---

## 文件结构

```
KlipperScreen-Theme-Woloong/
├── deploy.sh              # 安装工具
├── R_deploy.sh            # 撤销工具
├── panels/
│   └── splash_screen.py   # Woloong 品牌启动画面
└── woloong/               # 主题文件
    ├── style.css          # 主样式表
    ├── style.conf         # 图表颜色配置
    ├── background.svg     # 六边形蜂巢背景
    ├── Woloong_Logo.png   # 品牌 Logo
    ├── Woloong_Logo.svg   # 启动画面 Logo
    └── images/            # 107 个 SVG 图标
```

---

## 配色系统

| Token | 色值 | 用途 |
|-------|------|------|
| `color1` | `#ff0000` | 品牌主色、挤出机温度、主要操作 |
| `color2` | `#ff6b00` | 热量指示、升温操作 |
| `color3` | `#00cc66` | 成功确认、冷却、运行状态 |
| `color4` | `#4488ff` | 信息提示、网络功能 |
| `bg` | `#0a0a0f` | 窗口背景 |
| `buttons-bg` | `#13131a` | 面板按钮背景 |
| `active` | `#3a1515` | 按钮活跃态 |
| `error` | `#ff1a1a` | 紧急停止、错误提示 |

---

## 设计特性

- **六边形蜂巢背景**：直接呼应 Woloong Logo 几何 DNA
- **红色霓虹边框**：按钮活跃态释放品牌红色辉光
- **工业面板风格**：底部彩色边框 + 左侧强调线
- **Woloong 品牌启动画面**：垂直居中 Logo + 品牌文字 + 加载指示

---

## 开源许可

与 KlipperScreen 一致（GPL 兼容）。
