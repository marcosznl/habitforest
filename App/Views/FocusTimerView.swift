import EventKit
import SwiftUI

/// Pomodoro with a tree that grows through every stage, ambient sound and Calendar time blocks.
struct FocusTimerView: View {
    @Environment(HabitStore.self) private var store
    @Environment(FocusSession.self) private var session
    @Environment(EventKitManager.self) private var eventKit

    @State private var ambientVolume = AppGroup.defaults.double(forKey: SettingsKey.ambientVolume)
    @State private var plannedStart = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
    @State private var plannedMinutes = 25
    @State private var planFeedback: String? = nil

    private let presets = [15, 25, 45, 60, 90]

    var body: some View {
        @Bindable var session = session
        HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                DashboardHeader(title: "Foco", subtitle: "Plante uma árvore enquanto se concentra.") {}

                GlassCard(padding: 24) {
                    VStack(spacing: 18) {
                        ZStack {
                            Circle().stroke(.quaternary, lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: session.progress)
                                .stroke(selectedColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(.linear(duration: 0.5), value: session.progress)
                            VStack(spacing: 0) {
                                TreeView(species: selectedHabit?.species ?? .oak, stage: session.growthStage,
                                         tint: selectedColor, animated: session.phase == .running)
                                    .frame(width: 150, height: 150)
                                Text(session.remainingLabel)
                                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                            }
                        }
                        .frame(width: 280, height: 280)

                        HStack(spacing: 12) {
                            switch session.phase {
                            case .running:
                                Button("Pausar", systemImage: "pause.fill") { session.pause() }
                            case .paused:
                                Button("Continuar", systemImage: "play.fill") { session.start() }
                            case .idle, .finished:
                                Button("Começar", systemImage: "play.fill") { session.start() }
                                    .keyboardShortcut(.space, modifiers: [])
                            }
                            Button("Reiniciar", systemImage: "arrow.counterclockwise") { session.reset() }
                                .disabled(session.phase == .idle)
                        }
                        .controlSize(.large)
                        .buttonStyle(.borderedProminent)

                        if session.phase == .finished {
                            Label("Sessão concluída! Sua árvore cresceu.", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                GlassCard {
                    Form {
                        Picker("Hábito", selection: $session.habitID) {
                            Text("Sessão livre").tag(UUID?.none)
                            ForEach(store.activeHabits) { habit in
                                Text(habit.name).tag(UUID?.some(habit.id))
                            }
                        }
                        Picker("Duração", selection: Binding(get: { session.durationMinutes }, set: { session.setDuration($0) })) {
                            ForEach(durationOptions, id: \.self) { Text("\($0) min").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .disabled(session.isActive)
                        Picker("Som ambiente", selection: $session.ambient) {
                            ForEach(AmbientSound.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                        }
                        Slider(value: $ambientVolume, in: 0...1) { Text("Volume") }
                            .onChange(of: ambientVolume) { _, value in AudioManager.shared.setAmbientVolume(value) }
                        Toggle("Registrar sessão no Calendário", isOn: $session.logToCalendar)
                            .onChange(of: session.logToCalendar) { _, on in
                                if on && !eventKit.calendarAuthorized { Task { await eventKit.requestCalendarAccess() } }
                            }
                    }
                    .formStyle(.columns)
                }
            }
            .frame(maxWidth: 520)

            agenda
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .onAppear { eventKit.loadTodaysEvents() }
    }

    private var durationOptions: [Int] {
        var options = presets
        if let target = selectedHabit?.targetMinutes, target > 0, !options.contains(target) {
            options.append(target)
            options.sort()
        }
        return options
    }

    private var selectedHabit: Habit? { session.habitID.flatMap(store.habit(id:)) }
    private var selectedColor: Color { selectedHabit?.themeColor ?? .green }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Agenda de hoje").font(.title2.weight(.semibold)).padding(.top, 58)
            GlassCard {
                if !eventKit.calendarAuthorized {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Conecte o Calendário para ver seus compromissos e registrar blocos de foco.")
                            .foregroundStyle(.secondary)
                        Button("Permitir acesso ao Calendário") { Task { await eventKit.requestCalendarAccess() } }
                    }
                } else if eventKit.todaysEvents.isEmpty {
                    Text("Nenhum compromisso hoje — dia perfeito para plantar.").foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(eventKit.todaysEvents, id: \.calendarItemIdentifier) { event in
                            HStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(nsColor: event.calendar.color))
                                    .frame(width: 4, height: 28)
                                VStack(alignment: .leading) {
                                    Text(event.title ?? "Sem título").lineLimit(1)
                                    Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) – \(event.endDate.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Text("Agendar bloco de foco").font(.headline)
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    DatePicker("Início", selection: $plannedStart)
                    Stepper("Duração: \(plannedMinutes) min", value: $plannedMinutes, in: 5...240, step: 5)
                    HStack {
                        Button("Adicionar ao Calendário", systemImage: "calendar.badge.plus") { planBlock() }
                            .disabled(!eventKit.calendarAuthorized)
                        if let planFeedback { Text(planFeedback).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Spacer()
        }
    }

    private func planBlock() {
        let ok = eventKit.addFocusBlock(
            title: "🌲 Foco: \(selectedHabit?.name ?? "Sessão livre")",
            start: plannedStart,
            minutes: plannedMinutes,
            notes: "Bloco planejado no HabitForest."
        )
        planFeedback = ok ? "Bloco criado no calendário \(EventKitManager.calendarTitle)." : (eventKit.lastError ?? "Falhou.")
        Haptics.perform(ok ? .levelChange : .generic)
    }
}
