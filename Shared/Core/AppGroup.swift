import Foundation

/// Contêiner compartilhado entre o app e a extensão do widget.
///
/// O identificador vem do Info.plist (`HabitosAppGroupIdentifier`), que expande
/// `$(TeamIdentifierPrefix)` na compilação e por isso sempre bate com o entitlement.
enum AppGroup {
    static let identifier: String = {
        let fromPlist = Bundle.main.object(forInfoDictionaryKey: "HabitosAppGroupIdentifier") as? String
        if let fromPlist, !fromPlist.isEmpty, !fromPlist.contains("$(") { return fromPlist }
        return "com.marcosznl.habitos"
    }()

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = URL.applicationSupportDirectory.appending(path: "Hábitos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static let defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: identifier) ?? .standard
        defaults.register(defaults: [
            SettingsKey.hemisphere: Hemisphere.automatic.rawValue,
            SettingsKey.soundsEnabled: true,
            SettingsKey.hapticsEnabled: true,
            SettingsKey.floatingWindow: false,
            SettingsKey.useICloudDrive: true,
            SettingsKey.calendarLogging: false,
            SettingsKey.remindersSync: true,
            SettingsKey.effectsVolume: 0.6,
            SettingsKey.ambientVolume: 0.5,
            SettingsKey.focusContext: "any",
            SettingsKey.focusMute: false,
        ])
        return defaults
    }()
}

enum SettingsKey {
    static let hemisphere = "hemisphere"
    static let soundsEnabled = "soundsEnabled"
    static let hapticsEnabled = "hapticsEnabled"
    static let floatingWindow = "floatingWindow"
    static let useICloudDrive = "useICloudDrive"
    static let calendarLogging = "calendarLogging"
    static let remindersSync = "remindersSync"
    static let effectsVolume = "effectsVolume"
    static let ambientVolume = "ambientVolume"
    static let focusContext = "focusContext"
    static let focusMute = "focusMute"
}
