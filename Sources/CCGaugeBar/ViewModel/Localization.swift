// Localization.swift — minimal en/zh dictionary + a TFunc helper.
//
// Keep keys hierarchical (`kpi.token_total`, `usage.title`, …) so adding
// a new screen doesn't require flattening lookups. The reach is small
// enough that we don't bother with Localizable.strings; a Swift map
// gives us autocomplete + compile-time key consistency in one go.

import Foundation
import SwiftUI

public enum Lang: String, CaseIterable, Codable, Sendable {
    case system
    case en
    case zh
}

public enum L10n {

    private static let zhTable: [String: String] = [
        // Header
        "brand": "ccgauge",
        "header.page.overview": "概览",
        "header.page.usage": "用量",
        "header.detail": "详情",
        "header.preferences": "偏好设置",

        // Provider card
        "provider.unconfigured": "未配置 · 设置中启用",
        "provider.no_activity": "无活动",
        "provider.turns_unit": "轮",

        // Range bar
        "range.1d": "1D",
        "range.7d": "7D",
        "range.30d": "30D",
        "range.all": "全部",
        "source.all": "全部",
        "source.claude": "Claude",
        "source.codex": "Codex",

        // KPI grid
        "kpi.token_total": "Token 总量",
        "kpi.turns_n": "%@ 轮对话",
        "kpi.cost_est": "预估费用",
        "kpi.saved": "节省 %@",
        "kpi.io_token": "I/O Token",
        "kpi.in": "输入",
        "kpi.out": "输出",
        "kpi.cache_token": "缓存 Token",
        "kpi.hit": "命中",

        // Trend
        "trend.title.1d": "每小时趋势",
        "trend.title.7d": "每日趋势 · 近 7 天",
        "trend.title.30d": "每日趋势 · 近 30 天",
        "trend.metric.tokens": "Token",
        "trend.metric.cost": "费用",
        "trend.metric.active": "对话轮次",
        "trend.tooltip.today": "今天",

        // Distribution
        "dist.project_top5": "项目 Top 5",
        "dist.model_top5": "模型 Top 5",
        "dist.other": "其他",
        "dist.demo_project": "项目 %d",

        // Usage page
        "usage.title": "用量明细",
        "usage.subtitle": "当前筛选范围内 %@ 轮对话",
        "usage.search.placeholder": "搜索模型 / 项目 / 会话 / 工具...",
        "usage.export_csv": "导出 CSV",
        "usage.rows_label": "行",
        "usage.cols_label": "列",
        "usage.col.time": "时间",
        "usage.col.prompt": "提示",
        "usage.col.model": "模型",
        "usage.col.project": "项目",
        "usage.col.total": "总量",
        "usage.today": "今",
        "usage.chip.model": "模型",
        "usage.chip.project": "项目",
        "usage.chip.value.all": "全部",
        "usage.no_matching_rows": "没有匹配的记录",
        "usage.demo_project": "项目",

        // Row detail
        "row.duration": "耗时",
        "row.calls": "调用",
        "row.input": "输入",
        "row.output": "输出",
        "row.cache_read": "缓存读",
        "row.cache_write": "缓存写",
        "row.cost": "花费",
        "row.tools": "工具",
        "row.full_prompt": "完整提示",

        // Token tip
        "tip.title": "总量明细",
        "tip.token": "TOKEN",
        "tip.cost": "花费",
        "tip.in": "输入",
        "tip.out": "输出",
        "tip.cache_read": "缓存读",
        "tip.cache_write": "缓存写",
        "tip.total": "合计",

        // Footer
        "footer.synced": "已同步",
        "footer.syncing": "同步中…",
        "footer.sync_error": "同步失败 · 点击查看",
        "footer.refresh": "刷新",
        "footer.close": "关闭",

        // State cards
        "state.empty.title": "本时段暂无活动",
        "state.empty.desc": "所选范围内未发现 Claude / Codex 会话。\n在终端跑一次 `claude code` 或 `codex` 即可。",
        "state.error.title": "无法获取数据",
        "state.error.desc": "ccgauge 数据读取失败。\n请确认 ~/.claude 或 ~/.codex 目录可访问。",
        "state.welcome.title": "欢迎使用 ccgauge-bar",
        "state.welcome.desc": "第一次使用：先在终端跑一次 `claude code` 或 `codex`，\n让我们读到本机的会话日志。",
        "state.action.copy_cmd": "复制命令",
        "state.action.refresh": "刷新",
        "state.action.retry": "重试",
        "state.action.open_terminal": "打开终端",

        // Settings
        "settings.title": "偏好设置",
        "settings.tab.general": "通用",
        "settings.tab.data": "数据",
        "settings.tab.about": "关于",
        "settings.general.launch_at_login": "开机自启",
        "settings.general.shortcut": "唤出快捷键",
        "settings.general.shortcut.hint": "v1.1 引入",
        "settings.general.statusbar_style": "状态栏图标样式",
        "settings.general.style.icon": "仅图标",
        "settings.general.style.icon_cost": "图标 + 今日花费",
        "settings.general.style.icon_block": "图标 + 5h 进度",
        "settings.general.style.hint": "v1.1 引入；当前默认仅图标",
        "settings.general.language": "语言",
        "settings.general.language.system": "跟随系统",
        "settings.general.language.zh": "简体中文",
        "settings.general.language.en": "English",
        "settings.data.default_source": "默认数据源",
        "settings.data.default_range": "默认时间范围",
        "settings.data.default_sort": "默认排序",
        "settings.data.sort.cost": "按费用",
        "settings.data.sort.token": "按 token",
        "settings.data.demo": "演示模式",
        "settings.data.demo.hint": "项目名替换为项目 1 / 2 / 3，便于截图分享",
        "settings.data.currency": "货币",
        "settings.about.privacy": "ccgauge-bar 只在你点击图标时读取本机数据。\n不联网，不上传，无遥测。",
        "settings.about.github": "GitHub",
        "settings.about.issues": "Issues",
        "settings.about.privacy_link": "Privacy",
        "settings.about.check_update": "检查更新",

        // Context menu (right-click on status item)
        "ctx.open_dashboard": "打开看板",
        "ctx.refresh_now": "立即刷新",
        "ctx.preferences": "偏好设置…",
        "ctx.quit": "退出 ccgauge-bar"
    ]

    private static let enTable: [String: String] = [
        // Header
        "brand": "ccgauge",
        "header.page.overview": "Overview",
        "header.page.usage": "Usage",
        "header.detail": "Open",
        "header.preferences": "Preferences",

        // Provider card
        "provider.unconfigured": "Not configured · enable in Settings",
        "provider.no_activity": "No activity",
        "provider.turns_unit": "turns",

        // Range
        "range.1d": "1D",
        "range.7d": "7D",
        "range.30d": "30D",
        "range.all": "All time",
        "source.all": "All",
        "source.claude": "Claude",
        "source.codex": "Codex",

        // KPI
        "kpi.token_total": "Tokens",
        "kpi.turns_n": "%@ conversations",
        "kpi.cost_est": "Est. Cost",
        "kpi.saved": "saved %@",
        "kpi.io_token": "I/O Tokens",
        "kpi.in": "in",
        "kpi.out": "out",
        "kpi.cache_token": "Cache",
        "kpi.hit": "hit",

        // Trend
        "trend.title.1d": "Hourly",
        "trend.title.7d": "Daily · last 7 days",
        "trend.title.30d": "Daily · last 30 days",
        "trend.metric.tokens": "Tokens",
        "trend.metric.cost": "Cost",
        "trend.metric.active": "Turns",
        "trend.tooltip.today": "Today",

        // Distribution
        "dist.project_top5": "Top 5 Projects",
        "dist.model_top5": "Top 5 Models",
        "dist.other": "other",
        "dist.demo_project": "Project %d",

        // Usage
        "usage.title": "Usage",
        "usage.subtitle": "%@ conversations in this window",
        "usage.search.placeholder": "Search model / project / session / tool...",
        "usage.export_csv": "Export CSV",
        "usage.rows_label": "rows",
        "usage.cols_label": "cols",
        "usage.col.time": "Time",
        "usage.col.prompt": "Prompt",
        "usage.col.model": "Model",
        "usage.col.project": "Project",
        "usage.col.total": "Tokens",
        "usage.today": "Today",
        "usage.chip.model": "Model",
        "usage.chip.project": "Project",
        "usage.chip.value.all": "All",
        "usage.no_matching_rows": "No matching rows",
        "usage.demo_project": "Project",

        "row.duration": "Duration",
        "row.calls": "Calls",
        "row.input": "Input",
        "row.output": "Output",
        "row.cache_read": "Cache R",
        "row.cache_write": "Cache W",
        "row.cost": "Cost",
        "row.tools": "Tools",
        "row.full_prompt": "Full prompt",

        "tip.title": "Token Breakdown",
        "tip.token": "TOKEN",
        "tip.cost": "Cost",
        "tip.in": "Input",
        "tip.out": "Output",
        "tip.cache_read": "Cache R",
        "tip.cache_write": "Cache W",
        "tip.total": "Total",

        "footer.synced": "Synced",
        "footer.syncing": "Syncing…",
        "footer.sync_error": "Sync failed · click to view",
        "footer.refresh": "Refresh",
        "footer.close": "Close",

        "state.empty.title": "No activity in this window",
        "state.empty.desc": "No Claude / Codex sessions found in the selected range.\nRun `claude code` or `codex` in your terminal to start.",
        "state.error.title": "Unable to read data",
        "state.error.desc": "ccgauge couldn't read local data.\nCheck that ~/.claude or ~/.codex is accessible.",
        "state.welcome.title": "Welcome to ccgauge-bar",
        "state.welcome.desc": "First time? Run `claude code` or `codex` in your terminal\nso we can pick up your local session logs.",
        "state.action.copy_cmd": "Copy command",
        "state.action.refresh": "Refresh",
        "state.action.retry": "Retry",
        "state.action.open_terminal": "Open Terminal",

        "settings.title": "Preferences",
        "settings.tab.general": "General",
        "settings.tab.data": "Data",
        "settings.tab.about": "About",
        "settings.general.launch_at_login": "Launch at login",
        "settings.general.shortcut": "Hotkey",
        "settings.general.shortcut.hint": "Coming in v1.1",
        "settings.general.statusbar_style": "Status icon style",
        "settings.general.style.icon": "Icon only",
        "settings.general.style.icon_cost": "Icon + today's cost",
        "settings.general.style.icon_block": "Icon + 5h block",
        "settings.general.style.hint": "Coming in v1.1; defaults to icon only",
        "settings.general.language": "Language",
        "settings.general.language.system": "Follow system",
        "settings.general.language.zh": "简体中文",
        "settings.general.language.en": "English",
        "settings.data.default_source": "Default source",
        "settings.data.default_range": "Default range",
        "settings.data.default_sort": "Default sort",
        "settings.data.sort.cost": "By cost",
        "settings.data.sort.token": "By tokens",
        "settings.data.demo": "Demo mode",
        "settings.data.demo.hint": "Replace project names with Project 1/2/3 for screenshots",
        "settings.data.currency": "Currency",
        "settings.about.privacy": "ccgauge-bar reads local data only when you click the icon.\nNo network, no telemetry.",
        "settings.about.github": "GitHub",
        "settings.about.issues": "Issues",
        "settings.about.privacy_link": "Privacy",
        "settings.about.check_update": "Check for updates",

        "ctx.open_dashboard": "Open Dashboard",
        "ctx.refresh_now": "Refresh Now",
        "ctx.preferences": "Preferences…",
        "ctx.quit": "Quit ccgauge-bar"
    ]

    /// Resolve the effective Lang based on user preference + system.
    public static func resolve(_ pref: Lang) -> Lang {
        switch pref {
        case .en: return .en
        case .zh: return .zh
        case .system:
            // Look at the user's preferred languages; if anything zh, use zh.
            for code in Locale.preferredLanguages {
                if code.lowercased().hasPrefix("zh") { return .zh }
            }
            return .en
        }
    }

    public static func t(_ key: String, _ args: CVarArg..., lang: Lang) -> String {
        let table = (resolve(lang) == .zh) ? zhTable : enTable
        let template = table[key] ?? key
        if args.isEmpty { return template }
        return String(format: template, arguments: args)
    }
}
