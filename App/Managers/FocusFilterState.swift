import Foundation

/// What the active macOS Focus asked for, written by `HabitFocusFilter` and read by the store
/// and `NotificationManager`.
struct FocusFilterState: Equatable {
    static let didChangeNotification = Notification.Name("HabitForestFocusFilterDidChange")

    var context: HabitContext
    var muteReminders: Bool

    static var current: FocusFilterState {
        FocusFilterState(
            context: HabitContext(rawValue: AppGroup.defaults.string(forKey: SettingsKey.focusContext) ?? "") ?? .any,
            muteReminders: AppGroup.defaults.bool(forKey: SettingsKey.focusMute)
        )
    }

    static func apply(_ state: FocusFilterState) {
        AppGroup.defaults.set(state.context.rawValue, forKey: SettingsKey.focusContext)
        AppGroup.defaults.set(state.muteReminders, forKey: SettingsKey.focusMute)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
