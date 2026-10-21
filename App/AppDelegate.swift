import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = HabitStore.shared
        store.seedIfNeeded()
        store.drainPendingActions()
        store.publishSnapshot()

        NotificationManager.shared.configure()
        NotificationManager.shared.reschedule(for: store.habits)

        StatusItemController.shared.install()
        HotKeyManager.shared.onTrigger = { StatusItemController.shared.togglePopover() }
        HotKeyManager.shared.register()

        MainWindowController.shared.show()

        Task { await EventKitManager.shared.syncReminders(store: store) }

        // Day rollover: refresh trees, widget and reminders at midnight and when the Mac wakes.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppDelegate.refreshDay() }
        }
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { AppDelegate.refreshDay() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        HabitStore.shared.drainPendingActions()
        EventKitManager.shared.refreshStatus()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindowController.shared.show() }
        return true
    }

    /// Keep running in the menu bar after the window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// `habitforest://` links from the widget and Calendar events.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "habitforest" {
            let section: DashboardSection = switch url.host() {
            case "focus": .focus
            case "stats": .stats
            case "forest": .forest
            default: .everyday
            }
            MainWindowController.shared.show(section: section)
        }
    }

    private static func refreshDay() {
        let store = HabitStore.shared
        store.reload()
        store.publishSnapshot()
        NotificationManager.shared.reschedule(for: store.habits)
        Task { await EventKitManager.shared.syncReminders(store: store) }
    }
}
