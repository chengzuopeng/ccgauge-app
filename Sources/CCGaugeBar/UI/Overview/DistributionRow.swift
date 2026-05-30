// DistributionRow.swift — bottom row: Top-5 projects + Top-5 models.
//
// Per §8.5:
//   - sortMode toggle (money / hash icons) persisted as defaultSort
//   - source dot shows only when source = .all (claude/codex/other)
//   - demo mode renames projects to "Project 1..5"; other stays "other"

import SwiftUI

struct DistributionRowView: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        let overview = viewModel.overviewData()
        HStack(spacing: 8) {
            DistList(
                title: viewModel.t("dist.project_top5"),
                items: overview.projectItems,
                sortMode: $viewModel.sortMode,
                coloredBySource: viewModel.source == .all,
                lang: viewModel.lang
            )
            DistList(
                title: viewModel.t("dist.model_top5"),
                items: overview.modelItems,
                sortMode: $viewModel.sortMode,
                coloredBySource: viewModel.source == .all,
                lang: viewModel.lang
            )
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Item type

struct DistItem: Identifiable {
    let id: String
    let label: String
    let cost: Double
    let tokens: Int
    let source: String   // "claude" / "codex" / "other"
}

// MARK: - DistList view

private struct DistList: View {
    let title: String
    let items: [DistItem]
    @Binding var sortMode: SortMode
    let coloredBySource: Bool
    let lang: Lang

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            head
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(items) { it in
                        row(it, total: total)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var total: Double {
        items.reduce(0) { $0 + (sortMode == .cost ? $1.cost : Double($1.tokens)) }
    }

    private var head: some View {
        HStack {
            Text(title)
                .font(Theme.text(11, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 0) {
                sortBtn(MoneyIcon(size: 11, active: sortMode == .cost),
                        sortMode == .cost,
                        accessibilityLabel: L10n.t("settings.data.sort.cost", lang: lang)) {
                    sortMode = .cost
                }
                sortBtn(HashIcon(size: 11, active: sortMode == .token),
                        sortMode == .token,
                        accessibilityLabel: L10n.t("settings.data.sort.token", lang: lang)) {
                    sortMode = .token
                }
            }
            .padding(1)
            .background(Theme.bgSurfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    private func sortBtn<V: View>(_ icon: V,
                                  _ active: Bool,
                                  accessibilityLabel: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon
                .foregroundStyle(active ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(active ? Theme.bgBase : Color.clear)
                )
                .shadow(color: active ? .black.opacity(0.2) : .clear, radius: 0.5, x: 0, y: 1)
                // Whole 22×18 cell is clickable, not just the icon glyph.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func row(_ it: DistItem, total: Double) -> some View {
        let value = sortMode == .cost ? it.cost : Double(it.tokens)
        let pct = total > 0 ? (value / total * 100) : 0

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if coloredBySource {
                    Circle()
                        .fill(sourceColor(it.source))
                        .frame(width: 5, height: 5)
                }
                Text(it.label)
                    .font(Theme.text(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(sortMode == .cost ? Format.money(it.cost) : Format.token(it.tokens, lang: lang))
                    .font(Theme.num(11, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Theme.bgSurfaceHi2)
                        .frame(width: geo.size.width, height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 2))

                    Rectangle()
                        .fill(fillColor(it.source))
                        .frame(width: max(0, geo.size.width * CGFloat(pct) / 100), height: 4)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(height: 4)
            HStack {
                Spacer()
                Text(Format.pct(pct))
                    .font(Theme.num(10, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func sourceColor(_ s: String) -> Color {
        switch s {
        case "claude": return Theme.indigo
        case "codex":  return Theme.orange
        default:       return Theme.textQuaternary
        }
    }

    private func fillColor(_ s: String) -> Color {
        coloredBySource ? sourceColor(s) : Theme.indigo
    }
}
