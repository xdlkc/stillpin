# Stillpin

[English](./README.md) | 简体中文

**Stillpin** 是一款本地优先的原生 macOS 区域截图、标注与悬浮贴图工具，基于 Swift、AppKit 与 Apple ScreenCaptureKit 构建（支持 `macOS 13+`，Universal `arm64` + `x86_64`）。受「截图 → 标注 → 贴图」工作流启发，拥有独立标识与视觉设计，并非 Snipaste 的全功能克隆。

- **零依赖、纯本地运行**：不含网络代码、遥测、上传、截图历史记录或后台剪贴板监听；退出应用后编辑器与贴图即销毁。
- **不可逆平铺打码**：复制、保存 PNG 与贴图共用同一份平铺位图，遮盖区域直接替换像素，不嵌入原始底图或标注图层。
- **顺手的 macOS 快捷键**：默认提供 `F1`（区域截图）、`F3`（贴剪贴板图片）与 `Shift+F3`（显示/隐藏全部贴图），编辑器内支持 `⌘Z` / `⌘⇧Z` 撤销重做，并完整保留升级前的自定义键位。

## 快速开始与构建

需要 Xcode 15+（Swift 5.9+）与命令行工具，无任何第三方依赖或账号要求。

```bash
scripts/test.sh
scripts/build.sh
open dist/Stillpin.app
scripts/dmg.sh # 可选：打包 DMG
```

`scripts/build.sh` 会构建通用架构（`arm64` + `x86_64`）应用包、`dist/Stillpin-universal.zip` 与 SHA-256 校验文件（打包时由 `lipo` 验证双架构）。应用采用 ad-hoc 签名，未经过 Apple 公证；若 Gatekeeper 拦截首次运行，请在审查源码后通过系统设置的「仍要打开」放行。移动或重新构建 ad-hoc 应用可能需要重新授权屏幕录制权限。

## 核心用法

1. 启动 Stillpin 后菜单栏会出现图钉图标，首次运行自动打开设置页。
2. 在设置页点击 **Request Screen Recording**，并在「系统设置 → 隐私与安全性 → 屏幕录制」中手动允许 **Stillpin**（`app.xdlkc.stillpin`，本应用不采集任何音频）。
3. 触发 **Capture Region…**（`F1`），跨屏或单屏拖拽选区，松手进入标注编辑器（按 `Esc` 取消）。
4. 使用 **Arrow**（箭头）、**Box**（矩形）、**Text**（文字）或纯黑 **Cover**（遮盖）标注（`⌘Z` / `⌘⇧Z` 撤销重做），然后 **Copy**（`⌘C` / `Enter`）、**Save PNG…**（`⌘S`）或 **Pin**（`⌘T`）。
5. **Pin Clipboard Image**（`F3`）按需读取剪贴板图片贴图；**Open Image…**（`⌘O`）打开本地 PNG/JPEG/TIFF；**Synthetic Practice Image** 可在无需录屏权限的情况下体验编辑器。
6. 拖动贴图标题栏移动，拖动边缘/四角等比缩放，右键调节透明度（`20–100%`）或关闭贴图。

## 快捷键

| 场景 | 快捷键 | 功能 |
| --- | --- | --- |
| 全局 | `F1` | 区域截图 |
| 全局 | `F3` | 将剪贴板图片贴图 |
| 全局 | `Shift+F3` | 显示 / 隐藏全部贴图 |
| 编辑器 | `⌘C` / `Enter` | 复制平铺 PNG / 复制并关闭 |
| 编辑器 | `⌘S` | 保存 PNG 对话框 |
| 编辑器 | `⌘T` | 将标注结果贴图 |
| 编辑器 | `⌘Z` / `⌘⇧Z` | 撤销 / 重做 |
| 编辑器 | `T` / `Esc` | 选择文字工具 / 取消并关闭 |
| 选区遮罩 | `Esc` | 取消选区并移除遮罩 |
| 当前聚焦贴图 | `⌘W` / `Esc` | 关闭当前贴图 |

在 [Apple 键盘](https://support.apple.com/en-us/102650) 上若未开启标准功能键，可能需要按 `Fn+F1` / `Fn+F3` / `Fn+Shift+F3`。注册全局热键前会先检查 macOS 系统符号热键保留项，再尝试 Carbon 独占注册；发生冲突时原子回滚，不修改系统或其他应用的快捷键。升级时保留已有自定义设置，可在设置中点击 **Restore Snipaste Defaults** 恢复默认。

## 目录结构

```text
stillpin/
├── Package.swift                      # SwiftPM 清单（macOS 13+，零外部依赖）
├── Resources/Info.plist               # 应用元信息与 LSUIElement 配置
├── Sources/Stillpin/
│   ├── Main.swift                     # 入口与命令行验收参数
│   ├── App.swift                      # 菜单栏控制器、设置与权限引导
│   ├── Capture.swift                  # ScreenCaptureKit 多屏截图与坐标映射
│   ├── Imaging.swift                  # 标注模型、平铺 PNG 渲染与不可逆遮盖
│   ├── Windows.swift                  # 选区遮罩、标注编辑器与悬浮贴图窗口
│   ├── Shortcuts.swift                # Carbon 全局热键注册与旧配置迁移
│   └── CaptureVerification.swift      # 显式权限门控的合成窗口截屏自检
├── Tests/StillpinTests/               # 坐标几何、渲染、打码与快捷键回归测试
├── scripts/                           # test.sh、build.sh（Universal）、dmg.sh、icon.swift
├── PLAN.md                            # 范围与实现说明
└── VALIDATION.md                      # 实测验收记录与真机检查清单
```

## 能力边界

- **已实现**：菜单栏常驻、可配置全局热键、冻结式跨屏选区与混合 DPI 合成、箭头/矩形/文字/纯黑遮盖与撤销重做、平铺 PNG 复制/保存、截图与剪贴板悬浮贴图（拖拽/缩放/透明度/一键隐藏与关闭）、Universal ZIP/DMG 打包脚本与 GitHub Actions CI。
- **未包含**：OCR、窗口/元素自动吸附、滚动长截图、取色放大镜、截图历史与重启持久化、二次编辑已有标注、颜色/字体/线宽调节、马赛克、定时截图、开机自启、自动更新与 Apple 公证。
- 实测证据与待办物理设备核验见 [`VALIDATION.md`](./VALIDATION.md)。

## 验证

```bash
scripts/test.sh

# 可选：手动授予屏幕录制权限后验证真实 ScreenCaptureKit 捕获链路
open -n -W --stdout "$PWD/.build/real-capture.log" dist/Stillpin.app --args --verify-capture

# 可选：仅验证 Carbon 全局热键注册（不触发截图或剪贴板动作）
open -n -W --stdout "$PWD/.build/hotkey-registration.log" dist/Stillpin.app --args --verify-hotkeys
```
