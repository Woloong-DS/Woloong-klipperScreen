# Woloong Theme for KlipperScreen

## 品牌概述

专为 **Woloong** 品牌 3D 打印机设计的 KlipperScreen 主题，融合 DIY 创客文化与工业精密美学。

## 品牌视觉基因

| 元素 | 设计特征 | 含义 |
|------|---------|------|
| 主色 | 纯红 `#FF0000` | 力量、精密制造、工业警示 |
| 背景 | 深空黑 `#08080c` | 专业设备、沉浸式深色界面 |
| 几何 | 六边形蜂巢 | 模块化结构、机械精度 |
| 内影 | 工业岩板灰 `#212830` | 立体层次、CNC 加工质感 |

## 安装方式

### 方式一：自动化脚本安装（推荐）

从本仓库根目录执行：

```bash
# 安装主题
./scripts/install-woloong-theme.sh

# 如需指定非标准路径
./scripts/install-woloong-theme.sh --path /custom/path/to/KlipperScreen
```

脚本会自动完成：
1. 探测 KlipperScreen 安装路径（`~/KlipperScreen`、`/home/pi/KlipperScreen` 等）
2. 备份现有主题（如有）
3. 部署 `woloong` 主题文件到 `styles/` 目录
4. 修改 `KlipperScreen.conf`，添加 `theme = woloong`
5. 自动重启服务（可选）

### 方式二：独立 Patch 包安装

若需在其他设备上安装，使用 `patch/woloong-theme/` 目录：

```bash
# 打包分发
cd patch/woloong-theme
zip -r woloong-theme.zip .

# 在目标机器上解压后执行
./install.sh
```

Patch 包结构：
```
woloong-theme/
├── install.sh      # 自动安装脚本
├── uninstall.sh    # 卸载脚本
└── woloong/        # 完整主题文件
    ├── style.css
    ├── style.conf
    ├── background.svg
    └── images/
```

### 方式三：手动安装

1. 复制 `styles/woloong/` 到目标 `KlipperScreen/styles/` 目录
2. 编辑 `KlipperScreen.conf`：
   ```ini
   [main]
   theme = woloong
   ```
3. 重启服务：
   ```bash
   sudo systemctl restart KlipperScreen
   ```

## 卸载

```bash
# 从仓库卸载
./scripts/uninstall-woloong-theme.sh

# 或从 Patch 包卸载
./patch/woloong-theme/uninstall.sh
```

卸载脚本会自动：
- 删除 `styles/woloong/` 目录
- 备份并修改 `KlipperScreen.conf`，注释掉 `theme = woloong`
- 可选重启服务

## 文件清单

```
styles/woloong/
├── Woloong_Logo.png       # 品牌 Logo 参考
├── background.svg         # 六边形蜂巢科技背景（矢量 9.8KB）
├── style.css              # 主样式表（Woloong 品牌配色）
├── style.conf             # 温度图表颜色配置
├── README.md              # 本文件
└── images/                # 71 个 SVG 图标
```

## 配色系统

| Token | 色值 | 用途 |
|-------|------|------|
| `color1` | `#ff0000` | 品牌主色、挤出机温度、主要操作 |
| `color2` | `#ff6b00` | 热量指示、升温操作 |
| `color3` | `#00cc66` | 成功确认、冷却、运行状态 |
| `color4` | `#4488ff` | 信息提示、网络功能 |
| `bg` | `#08080c` | 窗口背景 |
| `bg-panel` | `#13131a` | 面板背景（玻璃质感） |
| `active` | `#ff0000` | 按钮活跃态 + 红色霓虹光晕 |
| `error` | `#ff1a1a` | 紧急停止、错误提示 |

## 设计特性

- **六边形蜂巢背景**：直接呼应 Woloong Logo 几何 DNA
- **红色霓虹光晕**：按钮活跃态释放品牌红色辉光
- **工业角标装饰**：四角六边形框架 + 刻度线（CNC/卡尺风格）
- **暗角聚焦**：边缘加深，内容区域突出
- **等宽字体控制台**：`JetBrains Mono`/`Fira Code` 增强工程感

## 基于原版

本主题基于 VZBot Carbon Fiber（Marco Formenton, VzBoT3D Team, 2022）改造，
保留完整 71 个 SVG 图标集，重写配色系统与背景设计以匹配 Woloong 品牌识别。

## 开源许可

与 KlipperScreen 及 VZBot 原始主题一致（GPL 兼容）。
