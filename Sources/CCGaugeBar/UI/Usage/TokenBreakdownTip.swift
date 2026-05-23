// TokenBreakdownTip.swift — the popover shown when hovering a row's
// Total column. 5-row table: 输入 / 输出 / 缓存读 / 缓存写 / 合计.

import SwiftUI

struct TokenBreakdownTip: View {
    let turn: UsageTurnRow
    let lang: Lang

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("tip.title", lang: lang))
                .font(Theme.text(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            // 3-column grid: label · TOKEN · 花费
            let columns = [
                GridItem(.fixed(72), alignment: .leading),
                GridItem(.fixed(60), alignment: .trailing),
                GridItem(.fixed(60), alignment: .trailing)
            ]

            LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                // Header (label cell empty)
                Text(" ").font(Theme.text(9.5, weight: .semibold))
                Text(L10n.t("tip.token", lang: lang))
                    .font(Theme.text(9.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.textTertiary)
                Text(L10n.t("tip.cost", lang: lang))
                    .font(Theme.text(9.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(Theme.textTertiary)

                row(dotColor: Theme.indigo,
                    label: L10n.t("tip.in", lang: lang),
                    tokens: turn.inputTokens, cost: turn.costInput)
                row(dotColor: Theme.success,
                    label: L10n.t("tip.out", lang: lang),
                    tokens: turn.outputTokens, cost: turn.costOutput)
                row(dotColor: Theme.orange,
                    label: L10n.t("tip.cache_read", lang: lang),
                    tokens: turn.cacheReadTokens, cost: turn.costCacheRead)
                row(dotColor: Color(hex: 0xC084FC),
                    label: L10n.t("tip.cache_write", lang: lang),
                    tokens: turn.cacheCreationTokens, cost: turn.costCacheWrite)
            }

            Rectangle().fill(Theme.border).frame(height: 1)

            // Total row
            HStack {
                Text(L10n.t("tip.total", lang: lang))
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(Format.token(turn.totalTokens, lang: lang))
                    .font(Theme.num(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(Format.money(turn.cost))
                    .font(Theme.num(12, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }

    private func row(dotColor: Color, label: String, tokens: Int, cost: Double) -> some View {
        Group {
            HStack(spacing: 6) {
                Rectangle().fill(dotColor)
                    .frame(width: 6, height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
                Text(label)
                    .font(Theme.text(11.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text(Format.token(tokens, lang: lang))
                .font(Theme.num(11.5, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text(Format.moneyTiny(cost))
                .font(Theme.num(11.5, weight: .medium))
                .foregroundStyle(Theme.success)
        }
    }
}
