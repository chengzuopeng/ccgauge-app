# ccgauge-bar

[![CI](https://github.com/chengzuopeng/ccgauge-app/actions/workflows/ci.yml/badge.svg)](https://github.com/chengzuopeng/ccgauge-app/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/chengzuopeng/ccgauge-app?include_prereleases&sort=semver)](https://github.com/chengzuopeng/ccgauge-app/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

macOS 菜单栏 app — Claude Code / Codex CLI 的 token 与费用速览。

- **形态**：常驻菜单栏，单击图标弹 popover（580×720 pt）。
- **数据来源**：直接读 `~/.claude/projects/**/*.jsonl` 和 `~/.codex/sessions/**/*.jsonl`。**不上传，无遥测**；默认零网络请求。一切对外网络都需要你**主动点击**触发：「检查更新」(`api.github.com`)、「详情↗」(本地 dashboard 不可用时打开项目官网)、Settings → About 的「GitHub / Issues / Privacy」三个外链 (跳 github.com 对应页面)。详见 [PRIVACY.md](PRIVACY.md)。
- **栈**：Swift 5.10+ + SwiftUI + AppKit；最低 macOS 13。Universal binary（Apple Silicon + Intel）。

## 下载安装

去 [Releases](https://github.com/chengzuopeng/ccgauge-app/releases/latest) 下最新的 `ccgauge-bar-*.dmg`，双击挂载后把 **CCGaugeBar.app** 拖到 **Applications**。

### 首次启动：放行 Gatekeeper

本工程是个人项目，目前**未做 Apple Developer ID 公证**（要 $99/年），用的是 ad-hoc 签名。macOS 首次启动会拦截：

> "无法打开 CCGaugeBar，因为 Apple 无法验证其是否包含恶意软件"

任选一种放行方式（**一次性**，之后双击就能直接开）：

- **GUI 方式**：在访达里**右键 → 打开**（不能双击），系统会弹更友好的确认框，点 "打开" 即可
- **命令行方式**：
  ```bash
  xattr -dr com.apple.quarantine /Applications/CCGaugeBar.app
  ```
  这条命令去掉 Gatekeeper 的"已隔离"属性

放行成功后，菜单栏右侧会出现 gauge 图标，单击弹 popover。

## 从源码编译

需要 macOS 13+ 和 Xcode Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/chengzuopeng/ccgauge-app.git
cd ccgauge-app
make run
```

常用 target：

```bash
make            # = make build（编译 universal release 二进制）
make bundle     # 打成 build/CCGaugeBar.app，含 icon 和 hardened runtime
make run        # bundle + open
make run-debug  # debug build，前台运行，日志在终端
make dmg        # 打 build/ccgauge-bar-<version>.dmg 安装包
make icon       # 重新生成 Resources/AppIcon.icns（设计变了才需要）
make test       # swift test
make clean      # 清理 .build/ 和 build/
make help       # 列出全部 target
```

第一次运行：菜单栏右侧会出现 gauge 图标，点一下弹 popover。

## 工程结构

```
.
├── Package.swift            # SwiftPM 工程定义
├── Info.plist               # bundle 元信息（LSUIElement=true）
├── Makefile                 # build + bundle + run
├── Sources/CCGaugeBar/
│   ├── CCGaugeBarApp.swift          # @main + AppDelegate（NSStatusItem + NSPopover）
│   ├── Models/                      # AssistantRecord / Pricing / Range / ParentLink
│   ├── Parsers/                     # Claude / Codex JSONL parsers + Dedup + ProjectLabel
│   ├── Domain/                      # Turns / Aggregator / Serialize
│   ├── Data/                        # ScanEngine actor + ScanStore + FileWatcher (FSEvents)
│   │                                # + ScanIndexPersistence (磁盘 cache) + PerfLog
│   ├── ViewModel/                   # PopoverViewModel + Localization (en/zh)
│   ├── UI/
│   │   ├── PopoverShell.swift       # 总外壳 + 四态分发
│   │   ├── Header.swift / Footer.swift / Theme.swift / Formatters.swift / Icons.swift
│   │   ├── Overview/                # 概览页：ProviderRow / RangeBar / KpiGrid / TrendChart / DistributionRow
│   │   ├── Usage/                   # 用量页：UsagePage / UsageRow / TokenBreakdownTip
│   │   ├── State/                   # 骨架 / 空 / 错误 / 欢迎
│   │   └── Settings/                # 偏好设置窗（General / Data / About）
│   └── Resources/                   # 图标 / favicon（SwiftPM bundle 资源）
└── Tests/CCGaugeBarTests/           # 单测：Pricing / Range / Format
```

## 发版流程（维护者向）

`Info.plist` 是版本号的唯一权威。`make bump` 帮你免去手编 XML。Release workflow 监听 `v*` tag 自动跑 CI + 打 DMG + 创建 GitHub Release。

```bash
# 1. 在 CHANGELOG.md 顶部新增一段 ## [1.0.1]，写改动
$EDITOR CHANGELOG.md

# 2. bump 版本（更新 Info.plist 的 CFBundleShortVersionString + build number）
make bump VERSION=1.0.1

# 3. 提交 + 打 tag + 推送
git commit -am "Release 1.0.1"
git tag v1.0.1
git push origin main --tags

# → GitHub Actions release.yml 会自动 build + 发布 DMG 到 Releases 页
```

CI 在每次 push / PR 时跑单测 + universal build + DMG 校验，产物可在 [Actions](https://github.com/chengzuopeng/ccgauge-app/actions) 里下载（保留 7 天）。

## 故障排查

| 现象 | 解决 |
|---|---|
| 编译报 `cannot find type 'NSPopover'` 类似错误 | 确认 `swift build` 在 macOS 上跑（不是 Linux） |
| 启动后菜单栏没有图标 | `Console.app` 搜 `CCGaugeBar` 看错误日志；或 `make run-debug` 看前台输出 |
| popover 弹出但显示"欢迎"页面 | 用户从未跑过 `claude` / `codex`，磁盘上没有 JSONL 文件 |
| popover 显示"无法获取数据" | 看 footer 错误提示；可能权限不足，确认 `~/.claude` 可读 |

## 隐私

详见 [PRIVACY.md](PRIVACY.md)。一句话版本：

- JSONL 数据**只在本机**读取，从不上传
- **默认零网络请求**；所有外网请求都需要你**主动点击**触发：「检查更新」(`api.github.com`)、「详情↗」(本地 dashboard 不可用时打开项目官网)、Settings → About 的「GitHub / Issues / Privacy」三个外链
- 无遥测、无崩溃上报
- `~/Library/Application Support/CCGaugeBar/cache/` 里缓存的是**解析后的索引 + 每条记录的前 200 字预览**（与界面用量页显示的内容一致），从不离开本机
- 安全问题报告流程见 [SECURITY.md](SECURITY.md)

## License

MIT
