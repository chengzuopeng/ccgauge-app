// RangeBar.swift — segmented 1D/7D/30D on the left, Source menu on the right.

import SwiftUI

struct RangeBarView: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        HStack {
            RangeSegment(range: $viewModel.range, options: [.d1, .d7, .d30], lang: viewModel.lang)
            Spacer()
            SourceMenu(source: $viewModel.source, lang: viewModel.lang)
        }
        .frame(height: 28)
    }
}

// MARK: - Segmented (1D / 7D / 30D)

struct RangeSegment: View {
    @Binding var range: Range
    let options: [Range]
    let lang: Lang

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { r in
                Button {
                    range = r
                } label: {
                    Text(r.displayLabel(lang: lang))
                        .font(Theme.text(12, weight: range == r ? .semibold : .medium))
                        .foregroundStyle(range == r ? .white : Theme.textSecondary)
                        .frame(minWidth: 38, minHeight: 22)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(range == r ? Theme.indigo : Color.clear)
                        )
                        .shadow(color: range == r ? .black.opacity(0.2) : .clear, radius: 1, x: 0, y: 1)
                        // Extend hit-test to the whole pill, not just text glyphs.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Source menu (uses native NSMenu via Menu)

struct SourceMenu: View {
    @Binding var source: SourceFilter
    let lang: Lang

    var body: some View {
        Menu {
            ForEach(SourceFilter.allCases, id: \.self) { s in
                Button {
                    source = s
                } label: {
                    HStack {
                        if source == s { Image(systemName: "checkmark") }
                        Text(s.displayLabel(lang: lang))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                accentDot
                Text(source.displayLabel(lang: lang))
                    .font(Theme.text(12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                ChevronDown(size: 10)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Theme.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var accentDot: some View {
        Group {
            switch source {
            case .all:
                Circle().fill(LinearGradient(colors: [Theme.indigo, Theme.orange],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
            case .claude:
                Circle().fill(Theme.indigo)
            case .codex:
                Circle().fill(Theme.orange)
            }
        }
        .frame(width: 8, height: 8)
    }
}
