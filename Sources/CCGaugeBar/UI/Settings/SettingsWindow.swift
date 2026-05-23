// SettingsWindow.swift — three-tab preferences window (480×360).
//
// Per design §12: General / Data / About tabs. Native window chrome (the
// AppDelegate creates the NSWindow with [.titled, .closable]), this view
// just owns the body.

import SwiftUI
import AppKit

struct SettingsRoot: View {
    @ObservedObject var viewModel: PopoverViewModel
    @State private var tab: Tab = .general
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = false

    enum Tab: String, CaseIterable { case general, data, about }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            Group {
                switch tab {
                case .general: GeneralTab(viewModel: viewModel, launchAtLogin: $launchAtLogin)
                case .data:    DataTab(viewModel: viewModel)
                case .about:   AboutTab(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bgBase)
        .frame(width: 480, height: 360)
        .onAppear(perform: syncWindowTitle)
        .onChange(of: viewModel.lang) { _ in syncWindowTitle() }
    }

    private func syncWindowTitle() {
        NSApp.keyWindow?.title = viewModel.t("settings.title")
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                tabButton(t)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.bgSurface)
    }

    @ViewBuilder
    private func tabButton(_ t: Tab) -> some View {
        let active = tab == t
        Button {
            tab = t
        } label: {
            VStack(spacing: 2) {
                Group {
                    switch t {
                    case .general: GearIcon(size: 16)
                    case .data:    HashIcon(size: 16, active: active)
                    case .about:   InfoIcon(size: 16)
                    }
                }
                Text(viewModel.t("settings.tab.\(t.rawValue)"))
                    .font(Theme.text(12, weight: .medium))
            }
            .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
            .frame(minWidth: 64)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? Theme.bgSurfaceHi : Color.clear)
            )
            // Click anywhere within the padded tab background, not just the
            // icon or text glyphs.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var viewModel: PopoverViewModel
    @Binding var launchAtLogin: Bool

    var body: some View {
        VStack(spacing: 0) {
            row(label: viewModel.t("settings.general.launch_at_login")) {
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            row(label: viewModel.t("settings.general.shortcut"),
                hint: viewModel.t("settings.general.shortcut.hint")) {
                HStack(spacing: 2) {
                    KbdView(text: "⌘")
                    KbdView(text: "⇧")
                    KbdView(text: "U")
                }
            }
            row(label: viewModel.t("settings.general.statusbar_style"),
                hint: viewModel.t("settings.general.style.hint")) {
                RadioGroup(
                    options: [
                        ("icon", viewModel.t("settings.general.style.icon")),
                        ("cost", viewModel.t("settings.general.style.icon_cost")),
                        ("block", viewModel.t("settings.general.style.icon_block"))
                    ],
                    selected: "icon",
                    onChange: { _ in /* v1.1 */ }
                )
            }
            row(label: viewModel.t("settings.general.language"), last: true) {
                Picker("", selection: $viewModel.lang) {
                    Text(viewModel.t("settings.general.language.system")).tag(Lang.system)
                    Text(viewModel.t("settings.general.language.zh")).tag(Lang.zh)
                    Text(viewModel.t("settings.general.language.en")).tag(Lang.en)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private func row<V: View>(label: String, hint: String? = nil, last: Bool = false,
                              @ViewBuilder _ control: () -> V) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 180, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    control()
                    if let hint = hint {
                        Text(hint)
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
            if !last { Divider().background(Theme.border) }
        }
    }
}

// MARK: - Data

private struct DataTab: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        VStack(spacing: 0) {
            row(label: viewModel.t("settings.data.default_source")) {
                RadioGroup(
                    options: [
                        ("all", viewModel.t("source.all")),
                        ("claude", viewModel.t("source.claude")),
                        ("codex", viewModel.t("source.codex"))
                    ],
                    selected: viewModel.source.rawValue,
                    onChange: { v in
                        viewModel.source = SourceFilter(rawValue: v) ?? .all
                    }
                )
            }
            row(label: viewModel.t("settings.data.default_range")) {
                RadioGroup(
                    options: [("1D", "1D"), ("7D", "7D"), ("30D", "30D")],
                    selected: viewModel.range.rawValue,
                    onChange: { v in
                        viewModel.range = Range(rawValue: v) ?? .d1
                    }
                )
            }
            row(label: viewModel.t("settings.data.default_sort")) {
                RadioGroup(
                    options: [
                        ("cost", viewModel.t("settings.data.sort.cost")),
                        ("token", viewModel.t("settings.data.sort.token"))
                    ],
                    selected: viewModel.sortMode.rawValue,
                    onChange: { v in
                        viewModel.sortMode = SortMode(rawValue: v) ?? .cost
                    }
                )
            }
            row(label: viewModel.t("settings.data.demo"),
                hint: viewModel.t("settings.data.demo.hint")) {
                Toggle("", isOn: $viewModel.demoMode)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            row(label: viewModel.t("settings.data.currency"), last: true) {
                Picker("", selection: $viewModel.currency) {
                    ForEach(["USD", "CNY", "EUR", "JPY"], id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private func row<V: View>(label: String, hint: String? = nil, last: Bool = false,
                              @ViewBuilder _ control: () -> V) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(Theme.text(12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 180, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    control()
                    if let hint = hint {
                        Text(hint)
                            .font(Theme.text(11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 9)
            if !last { Divider().background(Theme.border) }
        }
    }
}

// MARK: - About

private struct AboutTab: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.indigo, Theme.indigoStrong],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                GaugeIcon(size: 40, stroke: 1.8, foreground: .white)
            }
            .frame(width: 64, height: 64)
            .shadow(color: Theme.indigoDim.opacity(0.4), radius: 8, x: 0, y: 8)
            .padding(.bottom, 8)

            Text("ccgauge-bar \(appVersion())")
                .font(Theme.display(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(macOSDescription())
                .font(Theme.text(11))
                .foregroundStyle(Theme.textTertiary)

            Text(viewModel.t("settings.about.privacy"))
                .font(Theme.text(11.5))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 360)
                .padding(.top, 12)

            HStack(spacing: 8) {
                AboutLink(title: viewModel.t("settings.about.github"),
                          url: "https://github.com/")
                Text("·").foregroundStyle(Theme.textQuaternary)
                AboutLink(title: viewModel.t("settings.about.issues"),
                          url: "https://github.com/")
                Text("·").foregroundStyle(Theme.textQuaternary)
                AboutLink(title: viewModel.t("settings.about.privacy_link"),
                          url: "https://example.com/privacy")
                Text("·").foregroundStyle(Theme.textQuaternary)
                Button(viewModel.t("settings.about.check_update")) {
                    // v1.1 placeholder
                }
                .buttonStyle(.link)
                .foregroundStyle(Theme.indigo)
                .font(Theme.text(11))
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 8)
    }

    private func macOSDescription() -> String {
        let pi = ProcessInfo.processInfo
        let v = pi.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }

    private func appVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

private struct AboutLink: View {
    let title: String
    let url: String
    var body: some View {
        Button(action: {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        }) {
            Text(title)
                .font(Theme.text(11))
                .foregroundStyle(Theme.indigo)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable bits

private struct KbdView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.text(11, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Theme.bgSurfaceHi)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

private struct RadioGroup: View {
    let options: [(String, String)]
    let selected: String
    let onChange: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { (id, label) in
                let active = selected == id
                Button {
                    onChange(id)
                } label: {
                    Text(label)
                        .font(Theme.text(11, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(active ? Theme.bgSurfaceHi2 : Color.clear)
                        )
                        // Whole pill is clickable, not just the text glyphs.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Theme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
        .fixedSize()
    }
}
