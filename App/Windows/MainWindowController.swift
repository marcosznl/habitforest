import AppKit
import SwiftUI

/// Borderless-looking floating window: full-size content, transparent title bar, draggable by
/// its background, translucent behind-window material and optional always-on-top level.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()

    private var window: NSWindow?

    func show(section: DashboardSection? = nil) {
        if let section { DashboardNavigation.shared.section = section }
        let window = window ?? makeWindow()
        self.window = window
        applyFloatingPreference()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func applyFloatingPreference() {
        window?.level = AppGroup.defaults.bool(forKey: SettingsKey.floatingWindow) ? .floating : .normal
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "HabitForest"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self

        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState

        let hosting = NSHostingView(rootView: DashboardView().habitForestEnvironment())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        window.contentView = background
        window.contentMinSize = NSSize(width: 980, height: 600)
        window.center()
        window.setFrameAutosaveName("HabitForestMainWindow")
        return window
    }
}
