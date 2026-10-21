import AppKit

/// Force Touch trackpad feedback for toggles, drags and goals.
enum Haptics {
    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard AppGroup.defaults.bool(forKey: SettingsKey.hapticsEnabled) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    /// A short celebratory pattern for finished focus sessions.
    static func celebrate() {
        perform(.levelChange)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { perform(.levelChange) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { perform(.alignment) }
    }
}
