import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("Geral", systemImage: "gearshape") }
            IntegrationSettings().tabItem { Label("Integrações", systemImage: "calendar") }
            StorageSettings().tabItem { Label("Dados", systemImage: "icloud") }
        }
        .frame(width: 520, height: 380)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SettingsKey.hemisphere, store: AppGroup.defaults) private var hemisphere = Hemisphere.automatic.rawValue
    @AppStorage(SettingsKey.soundsEnabled, store: AppGroup.defaults) private var sounds = true
    @AppStorage(SettingsKey.effectsVolume, store: AppGroup.defaults) private var effectsVolume = 0.6
    @AppStorage(SettingsKey.hapticsEnabled, store: AppGroup.defaults) private var haptics = true
    @AppStorage(SettingsKey.floatingWindow, store: AppGroup.defaults) private var floating = false

    var body: some View {
        Form {
            Section("Janela") {
                Toggle("Manter janela flutuando acima das outras", isOn: $floating)
                    .onChange(of: floating) { _, _ in MainWindowController.shared.applyFloatingPreference() }
                LabeledContent("Atalho global", value: "⌘⇧H abre a floresta na barra de menus")
            }
            Section("Cenário") {
                Picker("Estações do ano", selection: $hemisphere) {
                    ForEach(Hemisphere.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section("Sensações") {
                Toggle("Sons orgânicos", isOn: $sounds)
                Slider(value: $effectsVolume, in: 0...1) { Text("Volume dos efeitos") }
                    .disabled(!sounds)
                Toggle("Resposta tátil no trackpad", isOn: $haptics)
                    .onChange(of: haptics) { _, on in if on { Haptics.perform(.levelChange) } }
            }
        }
        .formStyle(.grouped)
    }
}

private struct IntegrationSettings: View {
    @Environment(EventKitManager.self) private var eventKit
    @Environment(HabitStore.self) private var store
    @AppStorage(SettingsKey.remindersSync, store: AppGroup.defaults) private var remindersSync = false
    @State private var notificationsAuthorized = NotificationManager.shared.isAuthorized

    var body: some View {
        Form {
            Section("Notificações") {
                LabeledContent("Lembretes interativos") {
                    if notificationsAuthorized {
                        Label("Ativos", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Permitir") {
                            Task {
                                await NotificationManager.shared.requestAuthorization()
                                notificationsAuthorized = NotificationManager.shared.isAuthorized
                            }
                        }
                    }
                }
                Text("Os banners trazem os botões “Regar Árvore” e “Adiar 15 min”. Configure o filtro em Ajustes do Sistema › Foco › Filtros de Foco › HabitForest para silenciá-los.")
                    .font(.inter(.caption)).foregroundStyle(.secondary)
            }
            Section("Calendário e Lembretes") {
                LabeledContent("Calendário") {
                    if eventKit.calendarAuthorized {
                        Label("Conectado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Conectar") { Task { await eventKit.requestCalendarAccess() } }
                    }
                }
                Toggle("Sincronizar hábitos com o app Lembretes", isOn: $remindersSync)
                    .onChange(of: remindersSync) { _, on in
                        guard on else { return }
                        Task {
                            if !eventKit.remindersAuthorized { await eventKit.requestRemindersAccess() }
                            await eventKit.syncReminders(store: store)
                        }
                    }
                if let error = eventKit.lastError {
                    Text(error).font(.inter(.caption)).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct StorageSettings: View {
    @Environment(HabitStore.self) private var store
    @AppStorage(SettingsKey.useICloudDrive, store: AppGroup.defaults) private var useICloudDrive = true
    @State private var anchor: NSView? = nil

    private let persistence = PersistenceController.shared

    var body: some View {
        Form {
            Section("Banco de dados") {
                LabeledContent("Local atual", value: persistence.location.title)
                if let url = persistence.storeURL {
                    LabeledContent("Arquivo") {
                        Button(url.deletingLastPathComponent().path(percentEncoded: false)) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.link)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    }
                }
                Toggle("Salvar no iCloud Drive (HabitForest/)", isOn: $useICloudDrive)
                Text("A mudança vale na próxima abertura do app. Use o banco em um Mac por vez para evitar conflitos de sincronização.")
                    .font(.inter(.caption)).foregroundStyle(.secondary)
            }
            Section("Exportar") {
                Button("Compartilhar backup em JSON…", systemImage: "square.and.arrow.up") {
                    if let url = try? ExportService.writeJSON(for: store.habits) {
                        ExportService.share([url], from: anchor)
                    }
                }
                .background(ViewAnchor { anchor = $0 })
            }
        }
        .formStyle(.grouped)
    }
}
