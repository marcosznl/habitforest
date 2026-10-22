import AppKit

/// Resposta tátil do trackpad Force Touch ao marcar, arrastar e cumprir metas.
enum Haptics {
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard AppGroup.defaults.bool(forKey: SettingsKey.hapticsEnabled) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// Um padrão curto de comemoração ao terminar uma sessão de foco.
    static func celebrate() {
        perform(.levelChange)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { perform(.levelChange) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { perform(.alignment) }
    }
}
