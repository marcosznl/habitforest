import Foundation
import Observation

/// Pomodoro timer shared by the dashboard and the menu bar popover.
@MainActor
@Observable
final class FocusSession {
    static let shared = FocusSession()

    enum Phase { case idle, running, paused, finished }

    var habitID: UUID?
    var durationMinutes = 25
    var ambient: AmbientSound = .rain {
        didSet { if phase == .running { AudioManager.shared.setAmbient(ambient) } }
    }
    var logToCalendar: Bool = AppGroup.defaults.bool(forKey: SettingsKey.calendarLogging) {
        didSet { AppGroup.defaults.set(logToCalendar, forKey: SettingsKey.calendarLogging) }
    }

    private(set) var phase: Phase = .idle
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var startedAt: Date?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var endDate: Date?

    var total: TimeInterval { TimeInterval(durationMinutes * 60) }
    var progress: Double { total > 0 ? 1 - remaining / total : 0 }
    var isActive: Bool { phase == .running || phase == .paused }

    /// The tree grows through every stage during the session.
    var growthStage: GrowthStage {
        switch progress {
        case ..<0.05: .seed
        case ..<0.3: .sprout
        case ..<0.6: .young
        case ..<0.95: .mature
        default: .ancient
        }
    }

    var remainingLabel: String {
        let seconds = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func start(habitID: UUID? = nil, minutes: Int? = nil) {
        if let habitID { self.habitID = habitID }
        if let minutes { durationMinutes = minutes }
        if phase == .idle || phase == .finished {
            remaining = total
            startedAt = .now
        }
        endDate = Date.now.addingTimeInterval(remaining)
        phase = .running
        AudioManager.shared.setAmbient(ambient)
        Haptics.perform(.levelChange)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func pause() {
        guard phase == .running else { return }
        timer?.invalidate()
        phase = .paused
        AudioManager.shared.stopAmbient()
        Haptics.perform(.generic)
    }

    func reset() {
        timer?.invalidate()
        phase = .idle
        remaining = total
        startedAt = nil
        AudioManager.shared.stopAmbient()
    }

    func setDuration(_ minutes: Int) {
        durationMinutes = minutes
        if phase == .idle || phase == .finished { remaining = total }
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finish() }
    }

    private func finish() {
        timer?.invalidate()
        phase = .finished
        AudioManager.shared.stopAmbient()
        AudioManager.shared.play(.chime)
        Haptics.celebrate()

        let store = HabitStore.shared
        let habit = habitID.flatMap(store.habit(id:))
        if let habit { store.addFocusMinutes(durationMinutes, to: habit) }
        NotificationManager.shared.notifyFocusFinished(habitName: habit?.name, minutes: durationMinutes)
        if logToCalendar {
            EventKitManager.shared.addFocusBlock(
                title: "🌲 Foco: \(habit?.name ?? "Sessão livre")",
                start: startedAt ?? Date.now.addingTimeInterval(-total),
                minutes: durationMinutes,
                notes: "Sessão registrada pelo HabitForest."
            )
        }
    }
}
