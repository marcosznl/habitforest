import SwiftUI

/// Cria ou edita um hábito: nome, espécie, cor, meta de foco, contexto de Foco e lembrete.
struct HabitEditorView: View {
    @Environment(HabitStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let habit: Habit?

    @State private var name = ""
    @State private var species: TreeSpecies = .oak
    @State private var color: Color = Color(hex: TreeSpecies.oak.defaultHex)
    @State private var targetMinutes = 0
    @State private var context: HabitContext = .any
    @State private var reminderEnabled = false
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var greenhouse = false

    private let speciesColumns = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(habit == nil ? "Plantar novo hábito" : "Editar hábito")
                .font(.rubik(.title2))

            TextField("Nome do hábito", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.rubik(.title3))

            Text("Espécie").font(.rubik(.headline, weight: .semibold))
            LazyVGrid(columns: speciesColumns, spacing: 10) {
                ForEach(TreeSpecies.allCases) { option in
                    Button {
                        if color.hexString == species.defaultHex { color = Color(hex: option.defaultHex) }
                        species = option
                        Haptics.perform(.alignment)
                    } label: {
                        VStack(spacing: 2) {
                            TreeView(species: option, stage: .mature, tint: option == species ? color : nil,
                                     animated: option == species)
                                .frame(width: 64, height: 64)
                            Text(option.title).font(.inter(.caption))
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(option == species ? color.opacity(0.18) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(option == species ? color : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Form {
                ColorPicker("Cor do tema", selection: $color, supportsOpacity: false)
                Stepper(targetMinutes == 0 ? "Meta de foco: sem meta (apenas marcar)" : "Meta de foco: \(targetMinutes) min/dia",
                        value: $targetMinutes, in: 0...240, step: 5)
                Picker("Contexto (Modo Foco)", selection: $context) {
                    ForEach(HabitContext.allCases) { Label($0.title, systemImage: $0.symbolName).tag($0) }
                }
                Toggle("Lembrete diário", isOn: $reminderEnabled)
                if reminderEnabled {
                    DatePicker("Horário", selection: $reminderTime, displayedComponents: .hourAndMinute)
                }
                if habit != nil {
                    Toggle("Na Estufa (pausado, sequência congelada)", isOn: $greenhouse)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: reminderEnabled ? 250 : 210)

            HStack {
                if let habit {
                    Button("Excluir", role: .destructive) {
                        store.delete(habit)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancelar", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(habit == nil ? "Plantar" : "Salvar") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear(perform: load)
    }

    private func load() {
        guard let habit else { return }
        name = habit.name
        species = habit.species
        color = habit.themeColor
        targetMinutes = habit.targetMinutes
        context = habit.context
        reminderEnabled = habit.reminderEnabled
        reminderTime = Calendar.current.date(bySettingHour: habit.reminderHour, minute: habit.reminderMinute, second: 0, of: .now) ?? .now
        greenhouse = habit.isPausedInGreenhouse
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let target = habit ?? store.addHabit(name: trimmed, species: species, colorHex: color.hexString,
                                             targetMinutes: targetMinutes, context: context)
        target.name = trimmed
        target.species = species
        target.themeColorHex = color.hexString
        target.targetMinutes = targetMinutes
        target.context = context
        target.reminderEnabled = reminderEnabled
        let time = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        target.reminderHour = time.hour ?? 9
        target.reminderMinute = time.minute ?? 0
        if habit != nil, greenhouse != target.isPausedInGreenhouse {
            store.setGreenhouse(target, paused: greenhouse)
        }
        store.habitDidChange()
        if reminderEnabled { Task { await NotificationManager.shared.requestAuthorization() } }
        dismiss()
    }
}
