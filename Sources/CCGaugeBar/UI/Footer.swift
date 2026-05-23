// Footer.swift — bottom 28pt row: sync state + refresh / close buttons.

import SwiftUI

struct FooterView: View {
    @ObservedObject var viewModel: PopoverViewModel
    var onClose: () -> Void

    var body: some View {
        HStack {
            syncStateRow
            Spacer()
            actions
        }
        .frame(height: 28)
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var syncStateRow: some View {
        HStack(spacing: 6) {
            switch viewModel.scanStore.status {
            case .syncing, .scanning:
                RefreshIcon(size: 11, spin: true).foregroundStyle(Theme.textTertiary)
                Text(viewModel.t("footer.syncing"))
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.textSecondary)
            case .error:
                AlertIcon(size: 11).foregroundStyle(Theme.danger)
                Text(viewModel.t("footer.sync_error"))
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.danger)
            case .idle, .ready:
                RefreshIcon(size: 11).foregroundStyle(Theme.textTertiary)
                Text(viewModel.t("footer.synced"))
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.textSecondary)
                Text("·")
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.textQuaternary)
                Text(syncedAtText)
                    .font(Theme.num(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var syncedAtText: String {
        guard let d = viewModel.scanStore.lastSyncedAt else { return "——" }
        return Format.hhmmss(d)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(action: { Task { await viewModel.scanStore.scanNow(force: true) } }) {
                Text(viewModel.t("footer.refresh"))
            }
            .buttonStyle(FooterBtnStyle())
            .disabled(viewModel.scanStore.status == .syncing || viewModel.scanStore.status == .scanning)

            Button(action: onClose) {
                Text(viewModel.t("footer.close"))
            }
            .buttonStyle(FooterBtnStyle())
        }
    }
}

// MARK: - Generic footer button (.btn from styles.css)

struct FooterBtnStyle: ButtonStyle {
    var primary: Bool = false
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let bg: Color = {
            if primary {
                return hovered ? Theme.indigoStrong : Theme.indigo
            }
            return hovered ? Theme.bgSurfaceHi : Theme.bgSurface
        }()
        let fg: Color = primary ? .white : Theme.textPrimary
        let borderColor: Color = primary
            ? (hovered ? Theme.indigoStrong : Theme.indigo)
            : (hovered ? Theme.borderHi : Theme.border)

        return configuration.label
            .font(Theme.text(11, weight: .medium))
            .foregroundStyle(fg)
            .frame(height: 22)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .onHover { hovered = $0 }
    }
}
