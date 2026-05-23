# ccgauge-bar

macOS 菜单栏 app — Claude Code / Codex CLI 的 token 与费用速览。

- **形态**：常驻菜单栏，单击图标弹 popover（580×720 pt）。
- **数据来源**：直接读 `~/.claude/projects/**/*.jsonl` 和 `~/.codex/sessions/**/*.jsonl`。**不联网，不上传，无遥测。**
- **栈**：Swift 5.10+ + SwiftUI + AppKit；最低 macOS 13。

## 编译运行

```bash
# 一次性编译并启动
make run

# 仅编译 release 二进制
make build

# 仅打 .app bundle（不启动）
make bundle

# 开发模式（debug build，前台运行，日志在终端）
make run-debug

# 单测
make test

# 清理产物
make clean
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

## 故障排查

| 现象 | 解决 |
|---|---|
| 编译报 `cannot find type 'NSPopover'` 类似错误 | 确认 `swift build` 在 macOS 上跑（不是 Linux） |
| 启动后菜单栏没有图标 | `Console.app` 搜 `CCGaugeBar` 看错误日志；或 `make run-debug` 看前台输出 |
| popover 弹出但显示"欢迎"页面 | 用户从未跑过 `claude` / `codex`，磁盘上没有 JSONL 文件 |
| popover 显示"无法获取数据" | 看 footer 错误提示；可能权限不足，确认 `~/.claude` 可读 |

## 隐私

- 所有数据在本机读取
- 零网络请求
- 无任何遥测、崩溃上报
- 进程内不持久化任何会话内容（重启即丢，只缓存 file metadata）

## License

MIT
