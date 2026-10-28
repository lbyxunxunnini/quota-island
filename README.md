# 配额岛 · Quota Island

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.1.2-green.svg)](CHANGELOG.md)
![macOS](https://img.shields.io/badge/macOS-15.0%2B-black.svg)

配额岛是一个原生 macOS AI 额度监控 App，使用 SwiftUI 与 AppKit，在刘海区域和桌面面板中展示额度、余额与重置时间。

<img src="AIQuotaIsland/Resources/AppIcon-source.png" width="180" alt="配额岛双仪表图标">

## 功能

- 刘海精简视图、展开详情与桌面额度面板，共享同一份查询快照。
- 内置 Codex、OpenCode Go、DeepSeek、Kimi Code、GLM、MiniMax、OpenRouter 和 StepFun 适配器。
- 添加多个服务实例，设置名称、备注、排序、卡片样式及显示位置；Codex 使用本机登录，仅保留一个实例。
- 支持自定义 HTTP 请求与 JavaScript 额度提取脚本，提供本地脚本格式化和预览。
- 刷新间隔可选 1、3、5、10、15、30 分钟，默认 3 分钟，也可从菜单栏立即刷新。
- App 中配置的凭据保存在 macOS Keychain，普通显示配置保存在本机。

各服务需要相应账号或套餐凭据。内置适配器不代表所有服务均已完成实际账号验证；服务端接口变化也可能影响查询。

## 下载

当前版本为 **0.1.2**，可从 [GitHub Releases](https://github.com/lbyxunxunnini/quota-island/releases/tag/0.1.2) 下载适用于 Apple Silicon 与 Intel 的安装包。

本版修复 App 图标四角显示为直角的问题。

## 构建与运行

需要 macOS 15.0 或更高版本、Xcode 16.4（当前构建验证环境）。支持 Apple Silicon 与 Intel。

```sh
git clone https://github.com/lbyxunxunnini/quota-island.git
cd quota-island
xcodebuild -project AIQuotaIsland.xcodeproj -scheme AIQuotaIsland \
  -configuration Release -derivedDataPath build/Release build
codesign --force --sign - build/Release/Build/Products/Release/AIQuotaIsland.app
open build/Release/Build/Products/Release/AIQuotaIsland.app
```

也可以用 Xcode 打开 `AIQuotaIsland.xcodeproj`，选择 `AIQuotaIsland` Scheme 运行。上面的签名为本机临时签名，不是 Developer ID 签名或 Apple 公证。

启动后，从菜单栏图标打开「显示设置」，添加服务并验证凭据。Codex 自动读取本机 Codex 登录。自定义脚本使用 `{{apiKey}}` 或 `{{cookie}}` 引用凭据，不要把真实凭据写进脚本或仓库。

## 测试

```sh
xcodebuild -project AIQuotaIsland.xcodeproj -scheme AIQuotaIsland \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Tests test
```

测试覆盖额度响应解析、布局、实例隔离、自定义脚本和超时处理。模拟响应测试与本地构建不能代替实际账号查询和界面验证。

## 项目结构

- `AIQuotaIsland/Adapters/`：各服务的额度查询与解析。
- `AIQuotaIsland/Models/`：额度模型、服务目录、布局与样例。
- `AIQuotaIsland/Services/`：刷新协调、配置、Keychain、HTTP 和脚本执行。
- `AIQuotaIsland/UI/`：刘海、桌面面板、设置与卡片。
- `AIQuotaIsland/Resources/`：图标及离线格式化资源。
- `AIQuotaIslandTests/`：自动化测试。

## 开源许可

本项目按 [MIT License](LICENSE) 开源。第三方组件保留各自的版权与许可，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

版本记录见 [CHANGELOG.md](CHANGELOG.md)。

## 首个版本与后续计划

`0.1.0` 是配额岛的第一个版本。后续会逐步加入更多 AI 厂商的额度查询渠道，并持续优化配置和使用体验，争取让使用者能够以最便捷的方式查询与管理自己的 AI 额度。
