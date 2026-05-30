// ProviderRow.swift — two Provider Cards (Claude / Codex), 68pt tall each.
//
// Per §8.1:
//   - active when current source matches the card
//   - re-click selected card → flip back to .all (handled by VM.toggleProvider)
//   - muted when provider is not configured on disk
//   - subtitle shows "N turns · Xm" or "无活动" or "未配置 · 设置中启用"
//
// All stats come from `viewModel.providerStats(p)` and
// `viewModel.providerConfigured(p)`, which read the cached `turnRows` on
// the current scan. No per-render parent-chain walks (that was the prior
// O(N²) bug — see code review notes).

import SwiftUI

struct ProviderRowView: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        HStack(spacing: 8) {
            providerCard(.claude)
            providerCard(.codex)
        }
    }

    private func providerCard(_ p: ProviderId) -> some View {
        let active = viewModel.source.rawValue == p.rawValue
        let stats = viewModel.providerStats(p)
        return ProviderCard(
            providerId: p,
            label: p.displayName,
            plan: "—",                // see data-get.md §12.1 — not in JSONL
            turns: stats.turns,
            minutes: stats.minutes,
            configured: viewModel.providerConfigured(p),
            active: active,
            lang: viewModel.lang,
            accent: Theme.providerAccent(p),
            onClick: { viewModel.toggleProvider(p) }
        )
    }
}

// MARK: - Card view

private struct ProviderCard: View {
    let providerId: ProviderId
    let label: String
    let plan: String
    let turns: Int
    let minutes: Int
    let configured: Bool
    let active: Bool
    let lang: Lang
    let accent: Color
    let onClick: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onClick) {
            ZStack(alignment: .leading) {
                // Accent bar on the left edge
                Rectangle()
                    .fill(accent)
                    .frame(width: 3)
                    .padding(.vertical, 10)
                    .clipShape(RoundedRectangle(cornerRadius: 1))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(accent.opacity(0.18))
                            Text(String(label.prefix(1)))
                                .font(Theme.display(11, weight: .bold))
                                .foregroundStyle(accent)
                        }
                        .frame(width: 18, height: 18)

                        Text(label)
                            .font(Theme.display(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        Spacer(minLength: 0)

                        Text(plan)
                            .font(Theme.text(10, weight: .semibold))
                            .kerning(0.4)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.bgSurfaceHi2)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    subtitle
                        .padding(.leading, 26)   // align with name (logo width + gap)
                }
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 68)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(configured ? 1 : 0.55)
            // Whole 68pt card is the click target — defensively contentShape
            // even though the explicit frame + background usually gives us
            // full hit-test coverage on .plain buttons.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    /// Single-string description for VoiceOver: name + status. Reuses the
    /// same L10n keys the visible subtitle uses so VoiceOver and screen
    /// readers hear what sighted users see (in the user's chosen language),
    /// instead of the hardcoded English we had before.
    private var accessibilityDescription: String {
        if !configured {
            return "\(label) · \(L10n.t("provider.unconfigured", lang: lang))"
        }
        if turns == 0 {
            return "\(label) · \(L10n.t("provider.no_activity", lang: lang))"
        }
        let unit = L10n.t("provider.turns_unit", lang: lang)
        let minsSuffix = minutes > 0 ? " · \(Format.minutes(minutes))" : ""
        return "\(label) · \(turns) \(unit)\(minsSuffix)"
    }

    private var cardBg: Color {
        if active { return accent.opacity(0.08) }
        return hovered ? Theme.bgSurfaceHi : Theme.bgSurface
    }

    private var borderColor: Color {
        if active { return accent.opacity(0.6) }
        return hovered ? Theme.borderHi : Theme.border
    }

    @ViewBuilder
    private var subtitle: some View {
        if !configured {
            Text(L10n.t("provider.unconfigured", lang: lang))
                .font(Theme.text(11))
                .foregroundStyle(Theme.textTertiary)
        } else if turns == 0 {
            Text(L10n.t("provider.no_activity", lang: lang))
                .font(Theme.text(11))
                .foregroundStyle(Theme.textTertiary)
        } else {
            HStack(spacing: 4) {
                Text("\(turns.formatted())")
                    .font(Theme.num(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(L10n.t("provider.turns_unit", lang: lang))
                    .font(Theme.text(11))
                    .foregroundStyle(Theme.textSecondary)
                Text("·")
                    .foregroundStyle(Theme.textQuaternary)
                Text(Format.minutes(minutes))
                    .font(Theme.num(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
