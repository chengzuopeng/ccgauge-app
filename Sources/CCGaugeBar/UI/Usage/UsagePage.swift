// UsagePage.swift — turn-grouped table with expandable rows.

import SwiftUI

struct UsagePage: View {
    @ObservedObject var viewModel: PopoverViewModel
    @State private var searchText: String = ""
    @State private var committedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var expandedTurnId: String?
    @State private var sortAsc: Bool = false   // default: time desc
    @State private var page: Int = 0
    @State private var isExporting = false
    /// At most one row's token-breakdown tooltip is open at a time.
    /// Owned here (not inside each UsageRowView) so we can clear it on
    /// pagination, range/source/sort change, or page switch — preventing
    /// the popover from staying anchored to a row that's no longer visible.
    @State private var openTipFor: String?

    private let pageSize = 50

    var body: some View {
        let rowsData = viewModel.usageRows(query: committedSearchText, sortAsc: sortAsc)
        VStack(spacing: 8) {
            toolbar1(rowsData)
            toolbar2(rowsData)
            searchBar
            table(rowsData)
            pager(rowsData)
        }
        .onChange(of: viewModel.source) { _ in resetPaging() }
        .onChange(of: viewModel.range) { _ in resetPaging() }
        .onChange(of: sortAsc) { _ in resetPaging() }
        .onChange(of: viewModel.page) { _ in openTipFor = nil }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
            openTipFor = nil
        }
    }

    // MARK: - Toolbar 1: title + range

    private func toolbar1(_ data: UsageRowsData) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.t("usage.title"))
                    .font(Theme.display(16, weight: .semibold))
                    .kerning(-0.24)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 4) {
                    Text(viewModel.t("usage.subtitle", data.baseCount.formatted()))
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            RangeSegment(range: $viewModel.range,
                         options: [.d1, .d7, .d30, .all],
                         lang: viewModel.lang)
        }
    }

    // MARK: - Toolbar 2: chips + meta + export

    private func toolbar2(_ data: UsageRowsData) -> some View {
        HStack {
            HStack(spacing: 6) {
                SourceMenu(source: $viewModel.source, lang: viewModel.lang)
                UsageFilterChip(label: viewModel.t("usage.chip.model"),
                                value: viewModel.t("usage.chip.value.all"))
                UsageFilterChip(label: viewModel.t("usage.chip.project"),
                                value: viewModel.t("usage.chip.value.all"))
            }
            Spacer()
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(data.filteredCount.formatted())
                        .font(Theme.num(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(viewModel.t("usage.rows_label"))
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text("·").foregroundStyle(Theme.textQuaternary)
                HStack(spacing: 4) {
                    Text(viewModel.t("usage.cols_label"))
                        .font(Theme.text(11))
                        .foregroundStyle(Theme.textTertiary)
                    Text("6")
                        .font(Theme.num(11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                Button(action: exportCsv) {
                    Text(viewModel.t("usage.export_csv"))
                }
                .buttonStyle(FooterBtnStyle())
                .disabled(isExporting)
            }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        ZStack(alignment: .leading) {
            SearchIcon(size: 11)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 9)
            TextField(viewModel.t("usage.search.placeholder"), text: $searchText)
                .textFieldStyle(.plain)
                .font(Theme.text(12))
                .padding(.horizontal, 10)
                .padding(.leading, 16)   // room for icon
                .frame(height: 28)
                .background(Theme.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .onChange(of: searchText) { value in
                    scheduleSearchCommit(value)
                }
        }
    }

    // MARK: - Table

    private func table(_ data: UsageRowsData) -> some View {
        let rows = pageRows(data)
        return VStack(spacing: 0) {
            tableHeader
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { turn in
                        UsageRowView(turn: turn,
                                     expanded: expandedTurnId == turn.turnId,
                                     lang: viewModel.lang,
                                     currency: viewModel.currency,
                                     demoMode: viewModel.demoMode,
                                     tokenTipOpen: openTipFor == turn.turnId,
                                     onToggle: {
                                         expandedTurnId = expandedTurnId == turn.turnId ? nil : turn.turnId
                                     },
                                     onTokenTipTap: {
                                         openTipFor = openTipFor == turn.turnId ? nil : turn.turnId
                                     },
                                     onTokenTipDismiss: {
                                         if openTipFor == turn.turnId { openTipFor = nil }
                                     })
                    }
                    if rows.isEmpty {
                        Text(viewModel.t("usage.no_matching_rows"))
                            .font(Theme.text(12))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            // empty for chev col
            Color.clear.frame(width: 18)
            HStack(spacing: 4) {
                Text(viewModel.t("usage.col.time"))
                Image(systemName: sortAsc ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            // Frame first so the hit-test rect covers the whole 60pt cell,
            // then contentShape + tap gesture. The old order (tap → frame)
            // only registered clicks on the literal text/icon glyphs.
            .frame(width: 60, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { sortAsc.toggle() }

            Text(viewModel.t("usage.col.prompt"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(viewModel.t("usage.col.model"))
                .frame(width: 72, alignment: .leading)
            Text(viewModel.t("usage.col.project"))
                .frame(width: 76, alignment: .leading)
            Text(viewModel.t("usage.col.total"))
                .frame(width: 60, alignment: .trailing)
        }
        .font(Theme.text(10, weight: .semibold))
        .kerning(0.6)
        .textCase(.uppercase)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.bgSurfaceHi)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    // MARK: - Pagination / derived data

    private func pageCount(_ data: UsageRowsData) -> Int {
        max(1, Int(ceil(Double(data.filteredCount) / Double(pageSize))))
    }

    private func safePage(_ data: UsageRowsData) -> Int {
        min(max(0, page), pageCount(data) - 1)
    }

    private func pageRows(_ data: UsageRowsData) -> ArraySlice<UsageTurnRow> {
        let p = safePage(data)
        let start = p * pageSize
        let end = min(start + pageSize, data.rows.count)
        guard start < end else { return data.rows[0..<0] }
        return data.rows[start..<end]
    }

    @ViewBuilder
    private func pager(_ data: UsageRowsData) -> some View {
        let count = pageCount(data)
        let current = safePage(data)
        if count > 1 {
            HStack(spacing: 8) {
                Text("\(current + 1) / \(count)")
                    .font(Theme.num(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                pagerButton(systemName: "chevron.left.2", disabled: current == 0) {
                    setPage(0)
                }
                pagerButton(systemName: "chevron.left", disabled: current == 0) {
                    setPage(current - 1)
                }
                pagerButton(systemName: "chevron.right", disabled: current >= count - 1) {
                    setPage(current + 1)
                }
                pagerButton(systemName: "chevron.right.2", disabled: current >= count - 1) {
                    setPage(count - 1)
                }
            }
            .frame(height: 24)
        }
    }

    private func pagerButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? Theme.textQuaternary : Theme.textSecondary)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .disabled(disabled)
    }

    private func setPage(_ next: Int) {
        page = max(0, next)
        expandedTurnId = nil
        openTipFor = nil
    }

    private func resetPaging() {
        page = 0
        expandedTurnId = nil
        openTipFor = nil
    }

    private func scheduleSearchCommit(_ value: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                committedSearchText = value
                resetPaging()
            }
        }
    }

    // MARK: - CSV export

    private func exportCsv() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ccgauge-usage-\(Format.hhmmss(Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let rows = self.viewModel.usageRows(query: self.committedSearchText, sortAsc: self.sortAsc).rows
            self.isExporting = true
            Task.detached(priority: .utility) {
                let csv = Self.makeCsv(turns: rows)
                do {
                    try csv.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    PerfLog.logError("export.csv.error", error)
                }
                await MainActor.run {
                    self.isExporting = false
                }
            }
        }
    }

    /// CSV columns mirror ccgauge-refer's TURN_COLUMNS export (level=turn).
    nonisolated private static func makeCsv(turns: [UsageTurnRow]) -> String {
        let header = [
            "turn_id", "started_at", "ended_at", "duration_seconds",
            "source", "models", "effort", "project_name", "project_path",
            "session", "user_prompt", "tool_names",
            "input_tokens", "output_tokens", "reasoning_tokens",
            "cache_read_tokens", "cache_create_tokens", "total_tokens", "cost_usd"
        ]

        var lines: [String] = []
        lines.append("\u{FEFF}" + header.joined(separator: ","))   // UTF-8 BOM for Excel
        for t in turns {
            let row: [String] = [
                t.turnId,
                t.timestampIso,
                IsoDate.format(t.endTimestamp),
                "\(t.durationMs / 1000)",
                t.source.rawValue,
                t.models.joined(separator: ";"),
                t.efforts.joined(separator: ";"),
                ProjectLabel.projectNameFromCwd(t.cwd),
                t.cwd,
                t.sessionId,
                singleLine(t.userText),
                t.toolNames.joined(separator: ";"),
                "\(t.inputTokens)",
                "\(t.outputTokens)",
                "\(t.reasoningTokens)",
                "\(t.cacheReadTokens)",
                "\(t.cacheCreationTokens)",
                "\(t.totalTokens)",
                String(format: "%.6f", t.cost)
            ].map(csvEscape)
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated private static func csvEscape(_ raw: String) -> String {
        var s = raw
        // Formula-injection guard (Excel / Sheets): prefix `'` to neutralize.
        if let first = s.first, "=+-@\t\r".contains(first) {
            s = "'" + s
        }
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            s = "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    nonisolated private static func singleLine(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: " ")
         .replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\t", with: " ")
         .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Filter chip

struct UsageFilterChip: View {
    let label: String
    let value: String
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Theme.text(11.5, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(Theme.text(11.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            ChevronDown(size: 9)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(hovered ? Theme.bgSurfaceHi : Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .onHover { hovered = $0 }
    }
}
