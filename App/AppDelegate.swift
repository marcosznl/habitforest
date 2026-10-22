import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Typography.register()
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

        EventKitManager.shared.startObserving(store)
        Task { await EventKitManager.shared.prepareRemindersSync(store) }

        // Virada do dia: atualiza árvores, widget e lembretes à meia-noite e quando o Mac acorda.
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

    /// Continua rodando na barra de menus depois que a janela fecha.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Links `habitforest://` vindos do widget e dos eventos do Calendário.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "habitforest" {
            if url.host() == "barra" {
                StatusItemController.shared.showPopover()
                continue
            }
            let section: DashboardSection = switch url.host() {
            case "focus", "foco": .focus
            case "stats", "estatisticas": .stats
            case "forest", "floresta": .forest
            case "estufa": .greenhouse
            default: .habits
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
