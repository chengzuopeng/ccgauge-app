// StateCards.swift — the four placeholder body states:
//   skeleton (first scan, no data yet)
//   empty    (scan succeeded but no records in current filter)
//   error    (scan blew up)
//   welcome  (no JSONL anywhere on disk → first-time user)

import SwiftUI
import AppKit

// MARK: - Skeleton

struct SkeletonBody: View {
    @ObservedObject var viewModel: PopoverViewModel
    var body: some View {
        VStack(spacing: 10) {
            SkeletonProviderRow()
            SkeletonRangeBar()
            SkeletonKpi()
            SkeletonTrend()
            SkeletonDist()
        }
    }
}

private struct SkeletonProviderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<2) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    SkelRect(width: 90, height: 12)
                    SkelRect(width: 120, height: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 68)
                .padding(.horizontal, 14)
                .background(Theme.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
        }
    }
}

private struct SkeletonRangeBar: View {
    var body: some View {
        HStack {
            SkelRect(width: 130, height: 24).clipShape(Capsule())
            Spacer()
            SkelRect(width: 80, height: 24).clipShape(Capsule())
        }
        .frame(height: 28)
    }
}

private struct SkeletonKpi: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4) { _ in
                VStack(alignment: .leading) {
                    SkelRect(width: 56, height: 9)
                    Spacer(minLength: 0)
                    SkelRect(width: nil, height: 20).frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    SkelRect(width: nil, height: 9).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 84)
                .padding(10)
                .background(Theme.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
            }
        }
    }
}

private struct SkeletonTrend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SkelRect(width: 110, height: 12)
                Spacer()
                SkelRect(width: 130, height: 22).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<24, id: \.self) { i in
                    let h = 20 + (i * 37) % 70
                    SkelRect(width: nil, height: CGFloat(h))
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        // staggered breathe
                        .opacity(0.6)
                }
            }
            .frame(height: 100)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

private struct SkeletonDist: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<2) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SkelRect(width: 76, height: 11)
                        Spacer()
                        SkelRect(width: 48, height: 18).clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    ForEach(0..<5) { _ in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                SkelRect(width: 90, height: 10)
                                Spacer()
                                SkelRect(width: 36, height: 10)
                            }
                            SkelRect(width: nil, height: 4).frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
        }
        .frame(maxHeight: .infinity)
    }
}

private struct SkelRect: View {
    var width: CGFloat?
    var height: CGFloat
    @State private var opacity: Double = 0.4

    var body: some View {
        Rectangle()
            .fill(Theme.bgSurfaceHi2)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    opacity = 0.8
                }
            }
    }
}

// MARK: - Welcome / Empty / Error

struct WelcomeCard: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        StateCardLayout(
            accent: Theme.indigo,
            icon: AnyView(GaugeIcon(size: 36, stroke: 1.8, foreground: .white)
                .padding(10)
                .background(LinearGradient(colors: [Theme.indigo, Theme.indigoStrong],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))),
            title: viewModel.t("state.welcome.title"),
            desc: viewModel.t("state.welcome.desc"),
            actions: AnyView(HStack(spacing: 8) {
                Button(action: { copyToClipboard("claude") }) {
                    Text(viewModel.t("state.action.copy_cmd"))
                }
                .buttonStyle(FooterBtnStyle())

                Button(action: { openTerminal() }) {
                    Text(viewModel.t("state.action.open_terminal"))
                }
                .buttonStyle(FooterBtnStyle(primary: true))
            })
        )
    }
}

struct EmptyCard: View {
    @ObservedObject var viewModel: PopoverViewModel
    var onRefresh: () -> Void

    var body: some View {
        StateCardLayout(
            accent: Theme.indigo,
            icon: AnyView(GaugeIcon(size: 36, stroke: 1.8, foreground: .white)
                .padding(10)
                .background(LinearGradient(colors: [Theme.indigo, Theme.indigoStrong],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))),
            title: viewModel.t("state.empty.title"),
            desc: viewModel.t("state.empty.desc"),
            actions: AnyView(HStack(spacing: 8) {
                Button(action: { copyToClipboard("claude") }) {
                    Text(viewModel.t("state.action.copy_cmd"))
                }
                .buttonStyle(FooterBtnStyle())

                Button(action: onRefresh) {
                    Text(viewModel.t("state.action.refresh"))
                }
                .buttonStyle(FooterBtnStyle(primary: true))
            })
        )
    }
}

struct ErrorCard: View {
    var message: String
    @ObservedObject var viewModel: PopoverViewModel
    var onRetry: () -> Void

    var body: some View {
        StateCardLayout(
            accent: Theme.danger,
            icon: AnyView(AlertIcon(size: 28)
                .foregroundStyle(Theme.danger)
                .frame(width: 56, height: 56)
                .background(Theme.danger.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))),
            title: viewModel.t("state.error.title"),
            desc: viewModel.t("state.error.desc") + "\n\n" + message,
            actions: AnyView(HStack(spacing: 8) {
                Button(action: { copyToClipboard("ccgauge -v") }) {
                    Text(viewModel.t("state.action.copy_cmd"))
                }
                .buttonStyle(FooterBtnStyle())

                Button(action: onRetry) {
                    Text(viewModel.t("state.action.retry"))
                }
                .buttonStyle(FooterBtnStyle(primary: true))
            })
        )
    }
}

// MARK: - Shared layout

private struct StateCardLayout: View {
    let accent: Color
    let icon: AnyView
    let title: String
    let desc: String
    let actions: AnyView

    var body: some View {
        VStack(spacing: 12) {
            icon
            Text(title)
                .font(Theme.display(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(.init(desc))
                .font(Theme.text(12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .lineSpacing(2)
            actions
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Helpers

func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

func openTerminal() {
    let url = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    NSWorkspace.shared.open(url)
}
