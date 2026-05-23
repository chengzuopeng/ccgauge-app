// UsageRow.swift — one row of the usage table + its expanded detail.
//
// Layout (per §9.4 - §9.5):
//   chev | time | prompt | model | project | total
//   Click on row → expands the detail strip + full prompt.
//   Click on Total cell → toggles the per-token-type breakdown popover.
//
// Popover used to be hover-triggered, which is racy on macOS (mouse exits
// via the popover boundary fires false `onHover(false)`, causing flicker).
// Click-toggle is reliable and accessibility-friendlier.

import SwiftUI

struct UsageRowView: View {
    let turn: UsageTurnRow
    let expanded: Bool
    let lang: Lang
    let currency: String
    let demoMode: Bool
    /// Whether THIS row's token tooltip is the currently-open one.
    /// Owned by UsagePage so at most one tip is visible at a time.
    let tokenTipOpen: Bool
    let onToggle: () -> Void
    /// Called when the user clicks the Total cell — toggles whether
    /// this row owns the page's single tooltip slot.
    let onTokenTipTap: () -> Void
    /// Called by SwiftUI when the popover dismisses itself (click
    /// outside / Esc) — UsagePage clears its `openTipFor` slot.
    let onTokenTipDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            mainRow
            if expanded { detail }
        }
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: 8) {
            ChevronRight(size: 10)
                .foregroundStyle(expanded ? Theme.indigo : Theme.textTertiary)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .frame(width: 18, alignment: .leading)

            HStack(spacing: 4) {
                Text(dayLabel)
                    .font(Theme.text(10, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                Text(timeLabel)
                    .font(Theme.mono(11, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .frame(width: 60, alignment: .leading)

            Text(promptText)
                .font(Theme.text(11.5, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Circle()
                    .fill(turn.source == .claude ? Theme.indigo : Theme.orange)
                    .frame(width: 5, height: 5)
                Text(modelLabel)
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 72, alignment: .leading)

            Text(projectLabel)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 76, alignment: .leading)

            // Total — click toggles the breakdown popover. tokenTipOpen
            // is owned by UsagePage so at most one row's tip is visible.
            // The custom Binding wires SwiftUI's automatic dismiss (click
            // outside, Esc) back to the page so its slot gets cleared.
            Text(token(turn.totalTokens))
                .font(Theme.num(11.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .underline(true, color: tokenTipOpen ? Theme.textSecondary : Theme.textQuaternary)
                .frame(width: 60, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTokenTipTap()
                }
                .popover(isPresented: Binding(
                            get: { tokenTipOpen },
                            set: { newValue in if !newValue { onTokenTipDismiss() } }),
                         attachmentAnchor: .point(.bottom),
                         arrowEdge: .top) {
                    TokenBreakdownTip(turn: turn, lang: lang)
                        .padding(12)
                        .frame(minWidth: 220)
                        .background(Theme.bgSurfaceHi2)
                }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background(expanded ? Theme.bgSurfaceHi : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(expanded ? Color.clear : Theme.border).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 8-cell horizontal strip
            HStack(alignment: .top, spacing: 0) {
                detailCell("row.duration", value: Format.seconds(turn.durationMs / 1000))
                detailCell("row.calls", value: "\(turn.callCount)", divider: true)
                detailCell("row.input", value: token(turn.inputTokens), divider: true)
                detailCell("row.output", value: token(turn.outputTokens), divider: true)
                detailCell("row.cache_read", value: token(turn.cacheReadTokens),
                           accent: Theme.success, divider: true)
                detailCell("row.cache_write", value: token(turn.cacheCreationTokens),
                           divider: true)
                detailCell("row.cost", value: Format.money(turn.cost, currency: currency),
                           accent: Theme.success, divider: true)
                toolsCell
            }

            // Full prompt
            VStack(alignment: .leading, spacing: 4) {
                Text(t("row.full_prompt"))
                    .font(Theme.text(9.5, weight: .semibold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textTertiary)
                Text(turn.userText.isEmpty ? "—" : turn.userText)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.border).frame(height: 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .padding(.leading, 22)
        .background(Theme.bgSurfaceHi)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func detailCell(_ key: String, value: String,
                            accent: Color = Theme.textPrimary,
                            divider: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if divider {
                Rectangle().fill(Theme.border).frame(width: 1)
                    .padding(.trailing, 14)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(t(key))
                    .font(Theme.text(9.5, weight: .semibold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textTertiary)
                Text(value)
                    .font(Theme.num(13, weight: .medium))
                    .foregroundStyle(accent)
            }
            .padding(.trailing, 14)
        }
    }

    private var toolsCell: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(Theme.border).frame(width: 1)
                .padding(.trailing, 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(t("row.tools"))
                    .font(Theme.text(9.5, weight: .semibold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.textTertiary)
                if turn.toolNames.isEmpty {
                    Text("—").font(Theme.text(13)).foregroundStyle(Theme.textTertiary)
                } else {
                    HStack(spacing: 4) {
                        ForEach(turn.toolNames.prefix(6), id: \.self) { name in
                            Text(name)
                                .font(Theme.mono(10, weight: .medium))
                                .foregroundStyle(Theme.indigoStrong)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Theme.indigoBgSoft)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        if turn.toolNames.count > 6 {
                            Text("+\(turn.toolNames.count - 6)")
                                .font(Theme.mono(10, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Display helpers

    private var dayLabel: String {
        Format.isToday(turn.timestamp)
            ? t("usage.today")
            : Format.mdShort(turn.timestamp)
    }

    private var timeLabel: String {
        Format.hhmm(turn.timestamp)
    }

    private var promptText: String {
        turn.userText.isEmpty ? "—" : turn.userText
    }

    private var modelLabel: String {
        guard let m = turn.models.first else { return "—" }
        return Format.shortenModel(m)
    }

    private var projectLabel: String {
        demoMode ? t("usage.demo_project") : turn.projectLabel
    }

    private func t(_ key: String) -> String {
        L10n.t(key, lang: lang)
    }

    private func token(_ n: Int) -> String {
        Format.token(n, lang: lang)
    }
}
