// PopoverShell.swift — outer container of the popover.
//
// Layout (per app-design.md §6):
//   ┌─────────────────────────────────────────┐
//   │ Header (28pt)                           │
//   ├─────────────────────────────────────────┤
//   │ Banner (optional · CLI upgrade hint)    │
//   ├─────────────────────────────────────────┤
//   │ Body — Overview or Usage                │
//   ├─────────────────────────────────────────┤
//   │ Footer (28pt)                           │
//   └─────────────────────────────────────────┘
//
// The shell drives state-card switching (skeleton / empty / error /
// welcome) so the pages themselves don't need to handle those branches.

import SwiftUI

struct PopoverShell: View {
    @ObservedObject var viewModel: PopoverViewModel
    var onClose: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HeaderView(viewModel: viewModel,
                       onDetail: openDashboard,
                       onSettings: onOpenSettings)

            // Optional banner placeholder (CLI upgrade hint).
            // MVP: not shown. v1.1: check npm registry, gate on snooze.

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            FooterView(viewModel: viewModel, onClose: onClose)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 580, height: 720)
        .background(Theme.bgBase)
        // Theme tracking is automatic via NSApp.effectiveAppearance, and
        // formatters are explicit (we never use SwiftUI's locale-aware
        // formatters) — no need for preferredColorScheme/locale modifiers.
    }

    // MARK: - Body content (state-card or real page)

    @ViewBuilder private var content: some View {
        switch displayState {
        case .welcome:
            WelcomeCard(viewModel: viewModel)
        case .skeleton:
            SkeletonBody(viewModel: viewModel)
        case .error(let msg):
            ErrorCard(message: msg, viewModel: viewModel,
                      onRetry: { Task { await viewModel.scanStore.scanNow(force: true) } })
        case .empty:
            // Per §11 design: Provider Row + Footer still visible; only the
            // *middle* swaps to the empty card. We render Provider Row first
            // then the empty placeholder underneath.
            VStack(spacing: 10) {
                if viewModel.page == .overview {
                    ProviderRowView(viewModel: viewModel)
                    RangeBarView(viewModel: viewModel)
                }
                EmptyCard(viewModel: viewModel,
                          onRefresh: { Task { await viewModel.scanStore.scanNow(force: true) } })
            }
        case .ready:
            if viewModel.page == .overview {
                OverviewPage(viewModel: viewModel)
            } else {
                UsagePage(viewModel: viewModel)
            }
        }
    }

    // MARK: - State resolution

    private enum DisplayState: Equatable {
        case ready, skeleton, empty, error(String), welcome
    }

    private var displayState: DisplayState {
        switch viewModel.scanStore.status {
        case .error(let msg):
            return .error(msg)
        case .idle:
            return viewModel.scanStore.anyProviderDirExists() ? .skeleton : .welcome
        case .scanning:
            return viewModel.scanStore.scan == nil ? .skeleton : .ready
        case .syncing, .ready:
            // Empty vs ready check delegated to the ViewModel so we don't
            // re-scan ~18k records per render of PopoverShell.
            guard viewModel.scanStore.scan != nil else { return .skeleton }
            return viewModel.hasRecordsInWindow ? .ready : .empty
        }
    }

    private func openDashboard() {
        if let url = URL(string: "http://localhost:3737") {
            NSWorkspace.shared.open(url)
        }
    }
}

#if canImport(AppKit)
import AppKit
#endif
