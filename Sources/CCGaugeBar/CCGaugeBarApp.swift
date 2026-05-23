// CCGaugeBarApp.swift — @main entry point.
//
// We don't use SwiftUI's `WindowGroup`/`Scene` machinery for the main UI
// because a menubar app's primary surface is an `NSPopover` attached to
// an `NSStatusItem` — both of which are AppKit concepts. The SwiftUI
// `App` body is wired only to keep `@AppStorage` bindings + lifecycle
// callbacks alive; the actual UI is hosted by the AppDelegate.

import SwiftUI
import AppKit

@main
struct CCGaugeBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // A no-op settings scene keeps the menubar item from disappearing
        // when SwiftUI thinks there are no windows. The real Settings
        // window is opened by AppDelegate.openSettings().
        Settings { EmptyView() }
    }
}

// MARK: - AppDelegate

/// `@MainActor` so we can freely poke at SwiftUI/AppKit state. All
/// NSApplicationDelegate callbacks run on the main thread in practice;
/// this just lets Swift's concurrency checker verify it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private let scanStore = ScanStore()
    private lazy var viewModel = PopoverViewModel(scanStore: scanStore)

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private let statusItemLength: CGFloat = 24

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Pure menubar app — no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        installStatusItem()
        installPopover()

        // Kick off the first scan + start file watcher in the background.
        scanStore.start()
    }

    // MARK: status item

    private func installStatusItem() {
        // Fixed length keeps the highlighted menubar slot tight instead of
        // letting AppKit derive a too-wide width from the rendered bitmap.
        let item = NSStatusBar.system.statusItem(withLength: statusItemLength)
        item.length = statusItemLength
        statusItem = item

        if let button = item.button {
            // Render the gauge icon to a small bitmap. `isTemplate = true`
            // makes macOS auto-invert it based on menubar appearance.
            button.image = makeGaugeMenubarImage()
            button.image?.isTemplate = true
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "ccgauge-bar"
            button.frame.size.width = statusItemLength
        }
    }

    private func makeGaugeMenubarImage(size: CGFloat = 18, stroke: CGFloat = 1.8) -> NSImage {
        // Render the SAME SwiftUI GaugeIcon view used inside the app, via
        // ImageRenderer. This guarantees menubar and in-popover marks are
        // pixel-identical and avoids the SVG/NSImage Y-axis confusion that
        // produced the earlier garbled glyph.
        //
        // Menubar sizing: 18pt × 1.8pt stroke gives a tight glyph that
        // sits comfortably inside a 22pt squareLength status item button,
        // visually proportional to neighbouring SF-Symbol icons.
        //
        // ⚠️ Critical: ImageRenderer.nsImage returns an NSImage whose
        // reported `size` is the bitmap PIXEL dimensions (e.g. 36×36 for
        // an 18pt view at @2x). AppKit reads `image.size` to compute the
        // status button's intrinsic width — so without resetting `size`
        // back to the logical 18pt, the highlight rectangle balloons out
        // to ~50pt regardless of what NSStatusItem.length we pick.
        let view = GaugeIcon(size: size, stroke: stroke, foreground: .black)
            .frame(width: size, height: size)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        if let img = renderer.nsImage {
            img.size = NSSize(width: size, height: size)   // force logical-point sizing
            img.isTemplate = true
            return img
        }
        // Fallback: SF Symbol if ImageRenderer rendering fails.
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let fallback = NSImage(systemSymbolName: "gauge.medium",
                               accessibilityDescription: "ccgauge")?
            .withSymbolConfiguration(cfg) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }

    // MARK: popover

    private func installPopover() {
        let p = NSPopover()
        // The popover's content size MUST match the design's 580×720pt.
        // SwiftUI will lay out inside that.
        p.contentSize = NSSize(width: 580, height: 720)
        p.behavior = .transient  // closes on outside click / Esc / focus loss
        p.animates = true
        p.delegate = self
        p.contentViewController = NSHostingController(
            rootView: PopoverShell(viewModel: viewModel,
                                   onClose: { [weak self] in self?.closePopover() },
                                   onOpenSettings: { [weak self] in self?.openSettings() })
        )
        popover = p
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        switch event.type {
        case .rightMouseUp:
            showContextMenu()
        case .leftMouseUp:
            togglePopover()
        default:
            togglePopover()
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        // App must be active so the popover takes keyboard focus
        // (Esc to close, type into search box, etc.).
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        popover.close()
    }

    // MARK: right-click context menu

    private func showContextMenu() {
        let menu = NSMenu()

        let openDashboard = NSMenuItem(
            title: L10n.t("ctx.open_dashboard", lang: viewModel.lang),
            action: #selector(menuOpenDashboard), keyEquivalent: "d")
        openDashboard.target = self
        openDashboard.keyEquivalentModifierMask = [.command]
        menu.addItem(openDashboard)

        let refresh = NSMenuItem(
            title: L10n.t("ctx.refresh_now", lang: viewModel.lang),
            action: #selector(menuRefresh), keyEquivalent: "r")
        refresh.target = self
        refresh.keyEquivalentModifierMask = [.command]
        menu.addItem(refresh)

        menu.addItem(.separator())

        let prefs = NSMenuItem(
            title: L10n.t("ctx.preferences", lang: viewModel.lang),
            action: #selector(menuPreferences), keyEquivalent: ",")
        prefs.target = self
        prefs.keyEquivalentModifierMask = [.command]
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: L10n.t("ctx.quit", lang: viewModel.lang),
            action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        // Pop the menu directly anchored to the status button. The earlier
        // `statusItem.menu = menu; performClick; menu = nil` trick had
        // racy menu-close timing and would occasionally swallow the next
        // left-click — gone now.
        guard let button = statusItem.button else { return }
        // In the button's coordinate space (Y-up), a negative-Y location
        // anchors the menu BELOW the button. -4 leaves a small gap.
        let location = NSPoint(x: 0, y: -4)
        menu.popUp(positioning: nil, at: location, in: button)
    }

    @objc private func menuOpenDashboard() { openDashboardURL() }
    @objc private func menuRefresh() {
        Task { await scanStore.scanNow(force: true) }
    }
    @objc private func menuPreferences() { openSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    func openDashboardURL() {
        if let url = URL(string: "http://localhost:3737") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: settings window

    func openSettings() {
        if let w = settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        w.title = L10n.t("settings.title", lang: viewModel.lang)
        w.center()
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(
            rootView: SettingsRoot(viewModel: viewModel)
        )
        settingsWindow = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
