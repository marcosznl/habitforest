import Foundation
import SwiftData

/// Builds the SwiftData container. By default the store lives in the user's iCloud Drive
/// (`~/Library/Mobile Documents/com~apple~CloudDocs/HabitForest/`) so it follows the Mac
/// across reinstalls; it falls back to Application Support when iCloud Drive is unavailable.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    enum Location: Equatable {
        case iCloudDrive
        case local
        case inMemory

        var title: String {
            switch self {
            case .iCloudDrive: "iCloud Drive"
            case .local: "Este Mac"
            case .inMemory: "Memória (temporário)"
            }
        }
    }

    let container: ModelContainer
    let storeURL: URL?
    let location: Location

    static let schema = Schema([Habit.self, HabitLog.self])

    init(inMemory: Bool = false) {
        if inMemory {
            let config = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: Self.schema, configurations: config)
            storeURL = nil
            location = .inMemory
            return
        }

        let wantsICloud = AppGroup.defaults.bool(forKey: SettingsKey.useICloudDrive)
        var candidates: [(URL, Location)] = []
        if wantsICloud, let drive = Self.iCloudDriveDirectory() {
            candidates.append((drive.appending(path: "HabitForest.store"), .iCloudDrive))
        }
        candidates.append((Self.localDirectory().appending(path: "HabitForest.store"), .local))

        for (url, location) in candidates {
            let config = ModelConfiguration("HabitForest", schema: Self.schema, url: url, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: Self.schema, configurations: config) {
                self.container = container
                self.storeURL = url
                self.location = location
                return
            }
        }

        let config = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: Self.schema, configurations: config)
        storeURL = nil
        location = .inMemory
    }

    /// `~/Library/Mobile Documents/com~apple~CloudDocs/HabitForest`, created on demand.
    /// Requires the app to run outside the App Sandbox (see README).
    static func iCloudDriveDirectory() -> URL? {
        let cloudDocs = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: cloudDocs.path(percentEncoded: false)) else { return nil }
        let folder = cloudDocs.appending(path: "HabitForest", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    static func localDirectory() -> URL {
        let folder = URL.applicationSupportDirectory.appending(path: "HabitForest", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
