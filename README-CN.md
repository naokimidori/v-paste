<div align="center">
  <img src="docs/assets/brand/v-paste-icon.png" width="128" alt="V-Paste 应用图标">
  <h1>V-Paste</h1>
  <p><strong>一个快速、本地优先的 macOS 剪贴板历史应用。</strong></p>
  <p>
    <a href="README.md">English</a> ·
    <a href="README-CN.md">简体中文</a>
  </p>
  <p>
    <a href="https://github.com/naokimidori/v-paste/releases"><img alt="GitHub release" src="https://img.shields.io/github/v/release/naokimidori/v-paste?include_prereleases&style=for-the-badge"></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=for-the-badge&logo=apple">
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5-F05138?style=for-the-badge&logo=swift&logoColor=white">
    <img alt="Local first" src="https://img.shields.io/badge/local--first-private%20by%20default-20A67A?style=for-the-badge">
    <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/naokimidori/v-paste?style=for-the-badge"></a>
  </p>
  <img src="docs/assets/screenshots/hero.png" alt="V-Paste 主视觉截图">
</div>

V-Paste 帮你把剪贴板历史留在身边，而不是交给别人的服务器。它常驻菜单栏，自动记录文本、链接、文件和图片；当你需要找回内容时，用快捷键打开底部面板即可搜索、预览和再次粘贴。

## 灵感来源

V-Paste 的产品灵感借鉴自 [Paste](https://pasteapp.io/)，尤其是它的可视化剪贴板工作流、可搜索历史记录，以及很顺手的 Mac-first 交互体验。V-Paste 是一个独立开源项目，与 Paste 官方没有从属或合作关系，并更侧重本地优先的 macOS 实现。

## 快速导航

- [下载](#下载)
- [核心能力](#核心能力)
- [界面截图](#界面截图)
- [灵感来源](#灵感来源)
- [隐私模型](#隐私模型)
- [从源码构建](#从源码构建)
- [更新日志](CHANGELOG.md)

## 为什么做 V-Paste

剪贴板管理器的价值，是记住那些你很快会忘掉的内容；它的风险，也恰好来自“记住”。V-Paste 的设计原则很简单：剪贴板历史应该好用、可搜索，同时仍然只保存在你的 Mac 上。

| 方向 | V-Paste 提供什么 |
| --- | --- |
| 快速找回 | 底部浮动面板、搜索、类型筛选、键盘导航、一键写回剪贴板。 |
| 类型友好 | 文本、URL、复制的文件、图片会以不同卡片展示，而不是混成一条列表。 |
| 上下文完整 | 来源应用、时间、链接标题、favicon、图片尺寸、文件信息。 |
| 内容整理 | 收藏和分组让重要片段不会被历史流冲走。 |
| 隐私控制 | 本地 SQLite 存储、保留策略、清空历史、监听开关。 |
| 原生体验 | 菜单栏、全局快捷键、开机启动、SwiftUI 界面、AppKit 窗口行为。 |
| 轻量体积 | 聚焦原生能力，不引入账号体系、云同步服务或厚重运行时依赖。 |

## 核心能力

- **即时面板：** 按下全局快捷键，V-Paste 会像一个剪贴板命令中心一样从底部出现。
- **顺手搜索：** 支持按文本、URL、文件名、分组名、来源信息或单一内容类型过滤历史。
- **单选类型筛选：** 可从搜索旁的紧凑菜单中按图片、文本、链接或文件快速收窄历史。
- **丰富预览：** URL 卡片可展示页面标题和 favicon；图片卡片展示缩略图和像素尺寸。
- **收藏与分组：** 常用片段可以收藏，也可以移动到命名分组里长期保存。
- **本地优先：** 剪贴板历史存储在 macOS 的 Application Support 目录中。
- **默认轻量：** V-Paste 保持功能边界克制，不依赖云端服务链路。
- **无需账号：** 没有云端账号、没有 V-Paste 后端服务，本仓库也不包含分析埋点服务。

## 界面截图

### 剪贴板面板

![V-Paste 剪贴板面板](docs/assets/screenshots/clipboard-panel.png)

## 下载

可以从 [GitHub Releases](https://github.com/naokimidori/v-paste/releases/latest) 下载最新公开构建。

当前发布资产仍属于预览版本，适合测试开源基线，但还没有完成面向公开分发的签名和 notarization。如果 macOS 拦截下载的应用，建议从源码构建，或使用你自己的 Apple Developer 身份重新签名和公证。

默认使用流程：

1. 从最新 release 下载 DMG 或 ZIP。
2. 启动 `V-Paste.app`。
3. 点击菜单栏图标，或按 `Option + ~` 打开剪贴板面板。
4. 在设置里调整保留策略、开机启动、监听开关和显示面板快捷键。

## 隐私模型

V-Paste 默认本地优先。剪贴板记录会保存在你的 Mac 的 Application Support 目录中：

```text
~/Library/Application Support/io.vpaste.app/
```

应用可能保存剪贴板文本、复制文件路径、图片资源、缩略图、链接预览标题、favicon、来源应用名称、来源应用 bundle identifier、时间戳、收藏、分组和保留策略等元数据。

当复制内容是网页 URL 时，V-Paste 可能会请求该页面和 favicon，用于生成本地链接预览。它不需要账号，不会把剪贴板历史上传到 V-Paste 服务，本仓库也不包含分析或遥测采集服务。

完整的数据处理说明见 [PRIVACY.md](PRIVACY.md)。

## 从源码构建

环境要求：

- macOS 14 或更新版本
- 安装带 macOS SDK 的 Xcode
- 使用 Xcode 自带的 Swift 工具链

克隆并运行：

```bash
git clone https://github.com/naokimidori/v-paste.git
cd v-paste
./script/build_and_run.sh
```

常用开发模式：

```bash
./script/build_and_run.sh run
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --verify
```

运行测试：

```bash
xcodebuild test \
  -project V-Paste.xcodeproj \
  -scheme V-Paste \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData
```

打包本地 release 构建：

```bash
./script/package_release.sh
```

打包脚本会把未签名的本地构建产物写入 `dist/`。设置 `CODESIGN_IDENTITY` 可以签名暂存的 app；同时设置 `CODESIGN_IDENTITY` 和 `NOTARY_PROFILE` 可以在打包过程中提交并 staple DMG。发布流程见 [docs/release.md](docs/release.md)。

## 项目结构

```text
V-Paste/                  应用源码
  App/                    应用生命周期和状态 wiring
  Domain/                 剪贴板模型和值类型
  Infrastructure/         剪贴板、SQLite、文件缓存、热键服务
  Support/                通用支持工具
  UI/                     菜单栏、面板、卡片、设置界面
V-PasteTests/             XCTest 测试
script/                   本地构建和打包脚本
docs/                     公开文档和 README 素材
```

## 路线图

- 完成签名和 notarization 的 release 产物。
- 更细粒度的应用和内容忽略规则。
- 常用片段的导入/导出。
- 更多键盘操作和高级筛选控制。
- 更完整的新用户引导体验。

## 参与贡献

欢迎提交贡献。发起 Pull Request 前，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

适合优先参与的方向包括 UI 打磨、无障碍体验、测试覆盖、打包自动化，以及更注重隐私的过滤控制。

## 许可证

V-Paste 使用 [MIT License](LICENSE) 开源。
