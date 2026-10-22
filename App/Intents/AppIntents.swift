import AppIntents
import Foundation

/// Filtro de Foco: configure em Ajustes do Sistema › Foco › (Trabalho, Pessoal, Não Perturbe…) ›
/// Filtros de Foco › HabitForest. O sistema chama `perform()` quando o Foco liga e de novo,
/// com os valores padrão, quando ele desliga, o que reinicia o filtro.
struct HabitFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Filtrar hábitos"
    static var description: IntentDescription? = IntentDescription(
        "Mostra apenas os hábitos do contexto deste Foco e pode silenciar os lembretes."
    )

    @Parameter(title: "Mostrar hábitos de", default: .any)
    var context: HabitContext

    @Parameter(title: "Silenciar lembretes", default: false)
    var muteReminders: Bool

    var displayRepresentation: DisplayRepresentation {
        let mute = muteReminders ? " · lembretes silenciados" : ""
        return DisplayRepresentation(title: "Hábitos: \(context.title)\(mute)")
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocusFilterState.apply(FocusFilterState(context: context, muteReminders: muteReminders))
            NotificationManager.shared.reschedule(for: HabitStore.shared.habits)
        }
        return .result()
    }
}

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Iniciar sessão de foco"
    static var description = IntentDescription("Inicia o temporizador Pomodoro do app Hábitos.")
    static var openAppWhenRun = true

    @Parameter(title: "Minutos", default: 25, inclusiveRange: (1, 180))
    var minutes: Int

    @Parameter(title: "Hábito")
    var habit: HabitEntity?

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            FocusSession.shared.start(habitID: habit?.id, minutes: minutes)
            MainWindowController.shared.show(section: .focus)
        }
        return .result()
    }
}

struct OpenForestIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir Floresta"
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        await MainActor.run { MainWindowController.shared.show(section: .forest) }
        return .result()
    }
}

struct HabitForestShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleHabitIntent(),
            phrases: ["Regar árvore no \(.applicationName)", "Marcar hábito no \(.applicationName)"],
            shortTitle: "Regar Árvore",
            systemImageName: "drop.fill"
        )
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Iniciar foco no \(.applicationName)", "Começar Pomodoro no \(.applicationName)"],
            shortTitle: "Sessão de Foco",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: OpenForestIntent(),
            phrases: ["Abrir minha floresta no \(.applicationName)"],
            shortTitle: "Abrir Floresta",
            systemImageName: "tree.fill"
        )
    }
}
