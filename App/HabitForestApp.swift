import SwiftData
import SwiftUI

@main
struct HabitForestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A janela principal e o popover da barra de menus são gerenciados pelo AppKit (veja MainWindowController e
        // StatusItemController) para usar máscaras de estilo próprias do NSWindow e um atalho global.
        Settings {
            SettingsView()
                .habitForestEnvironment()
        }
        .commands { HabitCommands() }
    }
}

extension View {
    /// Injeta os serviços observáveis compartilhados e o contêiner do SwiftData.
    @MainActor
    func habitForestEnvironment() -> some View {
        Typography.register()
        return self
            .font(.inter(.body))
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
            // ⌘⇧H é registrado no sistema todo pelo HotKeyManager, então não é vinculado aqui também.
            Button("Mostrar barra de menus (⌘⇧H)") { StatusItemController.shared.togglePopover() }
        }
    }
}
