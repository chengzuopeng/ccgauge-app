// TrendChart.swift — bar chart (24 / 7 / 30 buckets, depending on Range).
//
// Per §8.4:
//   - 1D → 24 hourly buckets, X labels "00 06 12 18 24"
//   - 7D → 7 daily,   X labels 7 day strings
//   - 30D → 30 daily, X labels 7 sparse points
//   - metric: tokens (default) / cost / active
//   - source=all + metric=tokens → split bar: orange bottom (Codex), indigo top (Claude)

import SwiftUI

struct TrendChartView: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        let bars = viewModel.overviewData().trendBars
        let max = Swift.max(1.0, bars.map { visibleValue($0) }.max() ?? 1)

        VStack(alignment: .leading, spacing: 4) {
            // Section head
            HStack {
                Text(title)
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                MetricToggle(metric: $viewModel.metric, lang: viewModel.lang)
            }

            // Chart area
            ZStack(alignment: .bottom) {
                gridLines
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(bars.indices, id: \.self) { i in
                        bar(for: bars[i], maxValue: max)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .frame(height: 108)
            .overlay(alignment: .bottom) {
                xLabels(bars: bars)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    // MARK: - Title

    private var title: String {
        switch viewModel.range {
        case .d1:  return viewModel.t("trend.title.1d")
        case .d7:  return viewModel.t("trend.title.7d")
        case .d30: return viewModel.t("trend.title.30d")
        case .all: return viewModel.t("trend.title.30d")
        }
    }

    private func visibleValue(_ b: TrendBarVM) -> Double {
        switch viewModel.metric {
        case .tokens:
            switch viewModel.source {
            case .all:    return Double(b.claude + b.codex)
            case .claude: return Double(b.claude)
            case .codex:  return Double(b.codex)
            }
        case .cost:   return b.cost
        case .active: return Double(b.active)
        }
    }

    // MARK: - Bar view

    @ViewBuilder
    private func bar(for b: TrendBarVM, maxValue: Double) -> some View {
        let v = visibleValue(b)
        if v <= 0 {
            Rectangle().fill(Color.clear)
        } else {
            let h = (v / maxValue).clamped(to: 0...1)
            barFill(for: b)
                .frame(height: CGFloat(h) * 78)
                .clipShape(RoundedCorners(radius: 2, corners: [.topLeft, .topRight]))
        }
    }

    @ViewBuilder
    private func barFill(for b: TrendBarVM) -> some View {
        let metric = viewModel.metric
        switch metric {
        case .active:
            Rectangle().fill(Theme.success)
        case .cost:
            Rectangle().fill(Theme.indigoStrong)
        case .tokens:
            switch viewModel.source {
            case .all:
                // Split bar — orange (codex) at bottom, indigo on top.
                let total = Swift.max(1, b.claude + b.codex)
                let codexFrac = Double(b.codex) / Double(total)
                LinearGradient(stops: [
                    .init(color: Theme.orange, location: 0),
                    .init(color: Theme.orange, location: codexFrac),
                    .init(color: Theme.indigo, location: codexFrac),
                    .init(color: Theme.indigo, location: 1)
                ], startPoint: .bottom, endPoint: .top)
            case .codex:
                Rectangle().fill(Theme.orange)
            case .claude:
                Rectangle().fill(Theme.indigo)
            }
        }
    }

    // MARK: - Grid + labels

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<3) { _ in
                Rectangle().fill(Theme.border).frame(height: 0.5).opacity(0.5)
                Spacer()
            }
            Rectangle().fill(Theme.border).frame(height: 0.5).opacity(0.5)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private func xLabels(bars: [TrendBarVM]) -> some View {
        let labels: [String] = {
            switch viewModel.range {
            case .d1: return ["00", "06", "12", "18", "24"]
            case .d7: return bars.map { $0.label }
            case .d30, .all:
                // Sparse 7: first + 5 middle + last
                if bars.count <= 7 { return bars.map { $0.label } }
                let step = bars.count / 6
                var out: [String] = []
                for i in 0..<6 { out.append(bars[i * step].label) }
                out.append(bars.last!.label)
                return out
            }
        }()
        HStack {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i])
                    .font(Theme.num(9, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                if i < labels.count - 1 { Spacer() }
            }
        }
    }

}

// MARK: - Bar VM + Metric toggle

struct TrendBarVM {
    let label: String
    let claude: Int
    let codex: Int
    let cost: Double
    let active: Int
}

private struct MetricToggle: View {
    @Binding var metric: TrendMetric
    let lang: Lang

    var body: some View {
        HStack(spacing: 0) {
            tab(.tokens, label: L10n.t("trend.metric.tokens", lang: lang))
            tab(.cost,   label: L10n.t("trend.metric.cost", lang: lang))
            tab(.active, label: L10n.t("trend.metric.active", lang: lang))
        }
        .padding(2)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func tab(_ id: TrendMetric, label: String) -> some View {
        let active = metric == id
        Button {
            metric = id
        } label: {
            Text(label)
                .font(Theme.text(11, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? Theme.indigoStrong : Theme.textSecondary)
                .frame(height: 20)
                .padding(.horizontal, 9)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Theme.indigoBgSoft2 : Color.clear)
                )
                // Hit-test the whole pill, not just the text.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Per-corner rounded rect — bar corners are 2pt top, 1pt bottom in design.
struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: RectCorner

    struct RectCorner: OptionSet {
        let rawValue: Int
        static let topLeft     = RectCorner(rawValue: 1 << 0)
        static let topRight    = RectCorner(rawValue: 1 << 1)
        static let bottomLeft  = RectCorner(rawValue: 1 << 2)
        static let bottomRight = RectCorner(rawValue: 1 << 3)
        static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    func path(in rect: CGRect) -> Path {
        let tl = corners.contains(.topLeft)     ? radius : 0
        let tr = corners.contains(.topRight)    ? radius : 0
        let bl = corners.contains(.bottomLeft)  ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                        radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                        radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                        radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                        radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        return path
    }
}
