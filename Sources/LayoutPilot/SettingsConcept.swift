#if DEBUG
import AppKit
import SwiftUI

enum SettingsConcept: String, CaseIterable {
    case system = "A", compact = "B", progressive = "C"
    var name: String {
        switch self {
        case .system: return "Системные настройки"
        case .compact: return "Компактная панель"
        case .progressive: return "Сначала главное"
        }
    }
    var sections: [ConceptSection] {
        switch self {
        case .system: return [.main, .keys, .exceptions, .snippets, .appearance, .diagnostics]
        case .compact: return [.main, .keys, .sound, .snippets, .exceptions, .appearance, .application, .diagnostics]
        case .progressive: return [.main, .exceptions, .snippets, .diagnostics]
        }
    }
    var size: NSSize { NSSize(width: self == .compact ? 940 : 1000, height: self == .compact ? 660 : 740) }
}

enum ConceptSection: String, Identifiable, CaseIterable {
    case main, keys, exceptions, snippets, appearance, diagnostics, sound, application
    var id: String { rawValue }
    var title: String {
        switch self {
        case .main: return "Основное"
        case .keys: return "Клавиши"
        case .exceptions: return "Исключения"
        case .snippets: return "Сниппеты"
        case .appearance: return "Оформление"
        case .diagnostics: return "Проверка"
        case .sound: return "Звук"
        case .application: return "Приложение"
        }
    }
    var symbol: String {
        switch self {
        case .main: return "slider.horizontal.3"
        case .keys: return "keyboard"
        case .exceptions: return "hand.raised"
        case .snippets: return "text.badge.plus"
        case .appearance: return "paintpalette"
        case .diagnostics: return "checkmark.shield"
        case .sound: return "speaker.wave.2"
        case .application: return "gearshape"
        }
    }
}

/// Competing DEBUG shells share the existing settings bindings, lists and editors.
struct SettingsConceptView: View {
    @ObservedObject var store: Store
    let keyboard: KeyboardService
    let concept: SettingsConcept
    @State private var selection: ConceptSection?

    init(store: Store, keyboard: KeyboardService, concept: SettingsConcept, section: ConceptSection) {
        self.store = store
        self.keyboard = keyboard
        self.concept = concept
        _selection = State(initialValue: section)
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("TypeTune").font(.headline).padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 16)
                if concept == .compact {
                    List(selection: $selection) {
                        Section("Ввод") { sidebarRow(.main); sidebarRow(.keys); sidebarRow(.sound) }
                        Section("Текст") { sidebarRow(.snippets); sidebarRow(.exceptions) }
                        Section("Приложение") { sidebarRow(.appearance); sidebarRow(.application); sidebarRow(.diagnostics) }
                    }.listStyle(.sidebar)
                } else {
                    List(concept.sections, selection: $selection) { sidebarRow($0) }.listStyle(.sidebar)
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Label(store.serviceStatus.title, systemImage: store.running ? "checkmark.circle.fill" : "pause.circle")
                        .font(.caption).foregroundStyle(store.running ? Color.green : Color.secondary)
                    Text("dev · экспериментальная").font(.caption2).foregroundStyle(.secondary)
                }.padding(16)
            }
            .frame(minWidth: 188, idealWidth: 204, maxWidth: 220)
            .background(Color(nsColor: .windowBackgroundColor))
            VStack(spacing: 0) {
                HStack {
                    Text((selection ?? .main).title).font(concept == .compact ? .headline : .title2.bold())
                    Spacer()
                    if concept == .progressive {
                        Toggle("Пауза", isOn: $store.settings.paused).toggleStyle(.switch).controlSize(.small)
                            .fixedSize().disabled(!store.settingsStorageAvailable)
                    }
                }.padding(.horizontal, 24).padding(.vertical, concept == .compact ? 16 : 22)
                safetyNotice
                SettingsView(store: store, keyboard: keyboard, conceptSection: selection ?? .main, concept: concept)
                    .disabled(!store.settingsStorageAvailable)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.serviceStatus.message).font(.caption).lineLimit(1)
                        Text(store.lastStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Button("Сохранить отчёт…") { keyboard.saveDiagnosticReport() }.controlSize(.small)
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
            .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func sidebarRow(_ section: ConceptSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.symbol).foregroundStyle(Color.secondary).frame(width: 20)
        }
            .padding(.vertical, concept == .compact ? 1 : 5)
            .tag(section)
    }

    @ViewBuilder private var safetyNotice: some View {
        if !store.settingsStorageAvailable || !store.trusted || !store.listening || store.secure || store.recoveryRequired || store.outstandingInput > 0 {
            VStack(alignment: .leading, spacing: 8) {
                if !store.settingsStorageAvailable {
                    Label("Не удалось прочитать настройки", systemImage: "exclamationmark.triangle")
                    Text("Обработка и изменение настроек остановлены; исходные данные сохранены. Восстановите настройки из резервной копии и перезапустите приложение.").font(.caption)
                }
                if !store.trusted || !store.listening {
                    Label(!store.trusted ? "Нужен Универсальный доступ" : "Нужен Мониторинг ввода", systemImage: "hand.raised")
                    Text("Разрешите доступ в Системных настройках. Подключение проверяется автоматически.").font(.caption)
                    Button("Разрешить доступ") { keyboard.requestPermission() }
                }
                if store.secure {
                    Label("Защищённый ввод включён" + (store.secureInputOwner.map { " — его включило «\($0)»" } ?? ""), systemImage: "lock")
                    Text("Исправления приостановлены, пока он не выключится. Обычно его включают поле пароля, менеджер паролей или «Защищённая клавиатура» в Terminal.").font(.caption)
                }
                if store.textReviewRequired {
                    Label("Результат последней операции не подтверждён", systemImage: "exclamationmark.triangle")
                    Text("Проверьте последнее изменённое поле. Повторная отправка не выполняется. Неподтверждённых событий: \(store.uncertainInput). Обработка приостановлена.").font(.caption)
                    Button("Текст проверен — продолжить") { keyboard.confirmTextReviewed() }.disabled(store.outstandingInput > 0)
                }
                if store.pendingInput > 0 {
                    Text("Сохранено нажатий: \(store.pendingInput). Новый ввод проходит в активное окно. Для восстановления вернитесь в исходное поле и нажмите ⌘⌥R; текст и каретка должны совпадать.").font(.caption)
                    Button("Отбросить сохранённые нажатия…") { keyboard.discardPendingInput() }
                }
                if store.bufferedEvents > 0 { Text("Сохранено нажатий во время исправлений: \(store.bufferedEvents)").font(.caption) }
                if store.outstandingInput > 0 { Text("Ожидается подтверждение доставки: \(store.outstandingInput)").font(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.25)))
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
    }
}
#endif
