import AppKit
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Backup em JSON e o PNG "Retrato da Floresta", compartilhados pelo menu nativo do macOS.
@MainActor
enum ExportService {
    struct HabitExport: Codable {
        var id: UUID
        var name: String
        var treeType: String
        var themeColorHex: String
        var createdAt: Date
        var targetMinutes: Int
        var isPausedInGreenhouse: Bool
        var currentStreak: Int
        var bestStreak: Int
        var logs: [LogExport]
    }

    struct LogExport: Codable {
        var id: UUID
        var date: Date
        var isCompleted: Bool
        var minutesFocused: Int
        var dailyNote: String?
        var isFrozen: Bool
    }

    static func jsonData(for habits: [Habit]) throws -> Data {
        let payload = habits.map { habit in
            let summary = habit.summary
            return HabitExport(
                id: habit.id, name: habit.name, treeType: habit.treeType, themeColorHex: habit.themeColorHex,
                createdAt: habit.createdAt, targetMinutes: habit.targetMinutes,
                isPausedInGreenhouse: habit.isPausedInGreenhouse,
                currentStreak: summary.currentStreak, bestStreak: summary.bestStreak,
                logs: habit.logs.sorted { $0.date < $1.date }.map {
                    LogExport(id: $0.id, date: $0.date, isCompleted: $0.isCompleted, minutesFocused: $0.minutesFocused,
                              dailyNote: $0.dailyNote, isFrozen: $0.isFrozen)
                }
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func writeJSON(for habits: [Habit]) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "Habitos-\(DayMath.key(.now)).json")
        try jsonData(for: habits).write(to: url, options: .atomic)
        return url
    }

    static func portraitPNG(for habits: [Habit]) -> Data? {
        let renderer = ImageRenderer(content: ForestPortraitView(habits: habits).frame(width: 1200, height: 675))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func writePortrait(for habits: [Habit]) throws -> URL {
        guard let data = portraitPNG(for: habits) else { throw CocoaError(.fileWriteUnknown) }
        let url = URL.temporaryDirectory.appending(path: "Retrato da Floresta \(DayMath.key(.now)).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// NSSharingServicePicker nativo (AirDrop, Mensagens, Mail, Notas…) ancorado numa view.
    static func share(_ items: [Any], from view: NSView?) {
        guard let view = view ?? NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: items)
        let point = view.convert(view.window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        picker.show(relativeTo: CGRect(origin: point, size: CGSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
    }
}

/// Retrato transferível para o `ShareLink` do SwiftUI.
struct ForestPortrait: Transferable {
    let habitIDs: [UUID]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { portrait in
            let url = try await MainActor.run {
                let habits = HabitStore.shared.habits.filter { portrait.habitIDs.contains($0.id) }
                return try ExportService.writePortrait(for: habits)
            }
            return SentTransferredFile(url)
        }
        .suggestedFileName("Retrato da Floresta.png")
    }
}
