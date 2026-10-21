import SwiftData
import SwiftUI

@main
struct HabitForestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The main window and the menu bar popover are AppKit-managed (see MainWindowController and
        // StatusItemController) so they can use custom NSWindow style masks and a global hot key.
        Settings {
            SettingsView()
                .habitForestEnvironment()
        }
        .commands { HabitCommands() }
    }
}

extension View {
    /// Injects the shared observable services and the SwiftData container.
    @MainActor
    func habitForestEnvironment() -> some View {
        self
            .environment(HabitStore.shared)
            .environment(FocusSession.shared)
            .environment(EventKitManager.shared)
            .environment(DashboardNavigation.shared)
            .modelContainer(PersistenceController.shared.container)
    }
}

struct HabitCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Plantar hábito") {
                MainWindowController.shared.show()
                DashboardNavigation.shared.isAddingHabit = true
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Abrir Floresta") { MainWindowController.shared.show() }
                .keyboardShortcut("0", modifiers: .command)
        }

        CommandMenu("Hábitos") {
            ForEach(1...9, id: \.self) { number in
                Button("Regar hábito \(number)") {
                    let habits = HabitStore.shared.activeHabits
                    guard number - 1 < habits.count else { return }
                    HabitStore.shared.toggle(habits[number - 1])
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
            }
            Divider()
            ForEach(DashboardSection.allCases) { section in
                Button(section.title) { MainWindowController.shared.show(section: section) }
            }
            Divider()
            // ⌘⇧H is registered system-wide by HotKeyManager, so it is not bound here too.
            Button("Mostrar barra de menus (⌘⇧H)") { StatusItemController.shared.togglePopover() }
        }
    }
}
