// KpiGrid.swift — four cards, each 84pt tall:
//   ① Token 总量          ② 预估费用 (green)
//   ③ I/O Token           ④ 缓存 Token + hitRatio

import SwiftUI

struct KpiGridView: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        let overview = viewModel.overviewData()
        let totals = overview.totals
        let turns = overview.turnCount
        let hit = hitRatio(totals)

        HStack(spacing: 8) {
            KpiCard(
                title: viewModel.t("kpi.token_total"),
                main: token(totals.totalTokens),
                mainColor: Theme.textPrimary,
                subBuilder: AnyView(
                    Text(viewModel.t("kpi.turns_n", turns.formatted()))
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.textTertiary)
                )
            )
            KpiCard(
                title: viewModel.t("kpi.cost_est"),
                main: Format.money(totals.cost, currency: viewModel.currency),
                mainColor: Theme.success,
                subBuilder: AnyView(
                    Text(viewModel.t("kpi.saved", Format.money(totals.saved, currency: viewModel.currency)))
                        .font(Theme.text(10))
                        .foregroundStyle(Theme.success)
                )
            )
            KpiCard(
                title: viewModel.t("kpi.io_token"),
                main: token(totals.inputTokens + totals.outputTokens),
                mainColor: Theme.textPrimary,
                subBuilder: AnyView(
                    HStack(spacing: 4) {
                        Text(viewModel.t("kpi.in")).foregroundStyle(Theme.textTertiary)
                        Text(token(totals.inputTokens))
                            .font(Theme.num(10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        Text("·").foregroundStyle(Theme.textQuaternary)
                        Text(viewModel.t("kpi.out")).foregroundStyle(Theme.textTertiary)
                        Text(token(totals.outputTokens))
                            .font(Theme.num(10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .font(Theme.text(10))
                )
            )
            KpiCard(
                title: viewModel.t("kpi.cache_token"),
                main: token(totals.cacheReadTokens + totals.cacheCreationTokens),
                mainColor: Theme.textPrimary,
                subBuilder: AnyView(
                    HStack(spacing: 4) {
                        Text(viewModel.t("kpi.hit")).foregroundStyle(Theme.textTertiary)
                        Text("\(hit)%")
                            .font(Theme.num(10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .font(Theme.text(10))
                )
            )
        }
    }

    private func hitRatio(_ t: Totals) -> Int {
        let denom = t.inputTokens + t.cacheReadTokens + t.cacheCreationTokens
        guard denom > 0 else { return 0 }
        return Int((Double(t.cacheReadTokens) / Double(denom) * 100).rounded())
    }

    private func token(_ n: Int) -> String {
        Format.token(n, lang: viewModel.lang)
    }
}

// MARK: - Single KPI card

private struct KpiCard: View {
    let title: String
    let main: String
    let mainColor: Color
    let subBuilder: AnyView

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Theme.text(10, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)

            Spacer(minLength: 0)

            Text(main)
                .font(Theme.num(22, weight: .semibold))
                .foregroundStyle(mainColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)

            subBuilder
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 84)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(hovered ? Theme.bgSurfaceHi : Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .onHover { hovered = $0 }
        // Collapse the title / main number / sub into one VoiceOver string
        // so users hear "Token 总量: 1.2M, 192 轮对话" in one breath
        // instead of three separate elements.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(main))
    }
}
