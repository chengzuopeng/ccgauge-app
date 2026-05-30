// Header.swift — top row of the popover.
//
// Layout (per design §7.1):
//   [logo] ccgauge | [概览|用量]                 详情↗  ⚙

import SwiftUI

struct HeaderView: View {
    @ObservedObject var viewModel: PopoverViewModel
    var onDetail: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Brand
            BrandMark()
            Text(viewModel.t("brand"))
                .font(Theme.display(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .kerning(-0.065)   // -0.005em × 13

            Divider()
                .frame(width: 1, height: 14)
                .background(Theme.borderHi)
                .padding(.horizontal, 2)

            PageToggle(page: $viewModel.page, lang: viewModel.lang)

            Spacer()

            // 详情↗
            Button(action: onDetail) {
                HStack(spacing: 4) {
                    Text(viewModel.t("header.detail"))
                        .font(Theme.text(12, weight: .medium))
                    ExternalIcon()
                }
            }
            .buttonStyle(SecondaryIconButtonStyle())
            .accessibilityLabel(Text(viewModel.t("header.detail")))
            .accessibilityHint(Text(L10n.resolve(viewModel.lang) == .zh
                                     ? "在浏览器中打开 ccgauge 看板"
                                     : "Open ccgauge dashboard in browser"))

            // ⚙
            Button(action: onSettings) { GearIcon(size: 14) }
                .buttonStyle(SquareIconButtonStyle())
                .accessibilityLabel(Text(viewModel.t("header.preferences")))
        }
        .frame(height: 28)
    }
}

// MARK: - Brand mark (20×20 rounded gauge)

private struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [Theme.indigo, Theme.indigoStrong],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            GaugeIcon(size: 14, stroke: 1.8, foreground: .white)
        }
        .frame(width: 20, height: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
    }
}

// MARK: - Page toggle (概览 / 用量)

struct PageToggle: View {
    @Binding var page: PageId
    let lang: Lang
    @State private var hoveredTab: PageId?

    var body: some View {
        HStack(spacing: 0) {
            tab(.overview, label: L10n.t("header.page.overview", lang: lang))
            tab(.usage, label: L10n.t("header.page.usage", lang: lang))
        }
        .padding(2)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tab(_ id: PageId, label: String) -> some View {
        let active = page == id
        Button {
            page = id
        } label: {
            Text(label)
                .font(Theme.text(12, weight: active ? .semibold : .medium))
                .kerning(0.24)
                .foregroundStyle(active ? Theme.textPrimary
                                        : (hoveredTab == id ? Theme.textPrimary : Theme.textSecondary))
                .frame(height: 22)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(active ? Theme.bgBase : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(active ? Theme.borderHi : Color.clear, lineWidth: 0.5)
                )
                .shadow(color: active ? .black.opacity(0.25) : .clear, radius: 1, x: 0, y: 1)
                // Extend hit-test to the whole padded rect (not just text glyphs).
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { hoveredTab = id } else if hoveredTab == id { hoveredTab = nil } }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Button styles

struct SecondaryIconButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovered ? Theme.textPrimary : Theme.textSecondary)
            .frame(height: 28)
            .padding(.horizontal, 9)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovered ? Theme.bgSurfaceHi : Color.clear)
            )
            .onHover { hovered = $0 }
    }
}

struct SquareIconButtonStyle: ButtonStyle {
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hovered ? Theme.textPrimary : Theme.textSecondary)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovered ? Theme.bgSurfaceHi : Color.clear)
            )
            .onHover { hovered = $0 }
    }
}
