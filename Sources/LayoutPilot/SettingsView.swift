import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import LayoutPilotCore

struct SettingsView: View {
    @ObservedObject var store: Store
    let keyboard: KeyboardService
    @StateObject private var form = SettingsForm()
    @State private var selection: SettingsSection? = .main

    init(store: Store, keyboard: KeyboardService) {
        self.store = store
        self.keyboard = keyboard
    }
    #if DEBUG
    init(store: Store, keyboard: KeyboardService, renderSection: SettingsSection) {
        self.init(store: store, keyboard: keyboard)
        _selection = State(initialValue: renderSection)
    }
    #endif
    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Text("TypeTune").font(.headline).padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 16)
                List(SettingsSection.allCases, selection: $selection) { section in
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(systemName: section.symbol).foregroundStyle(Color.secondary).frame(width: 20)
                    }.padding(.vertical, 5).tag(section)
                }.listStyle(.sidebar).accessibilityLabel("Разделы настроек")
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Label(store.serviceStatus.title, systemImage: store.running && !store.recoveryRequired ? "checkmark.circle.fill" : "pause.circle")
                        .font(.caption).foregroundStyle(store.running && !store.recoveryRequired ? Color.green : Color.secondary)
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · экспериментальная")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Выйти") { NSApp.terminate(nil) }.controlSize(.small)
                }.padding(16)
            }
            .frame(minWidth: 188, idealWidth: 204, maxWidth: 220)
            .background(Color(nsColor: .windowBackgroundColor))
            VStack(spacing: 0) {
                HStack {
                    Text((selection ?? .main).title).font(.title2.bold())
                    Spacer()
                }.padding(.horizontal, 24).padding(.vertical, 22)
                safetyNotice
                sectionContent
                    .disabled(!store.settingsStorageAvailable)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity).clipped()
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.serviceStatus.message).font(.caption).lineLimit(2)
                        Text("Последнее событие: " + store.lastStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    Button("Сохранить отчёт…") { keyboard.saveDiagnosticReport() }.controlSize(.small)
                }.padding(.horizontal, 20).padding(.vertical, 12)
            }
            .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(minWidth: 920, idealWidth: 1000, minHeight: 640, idealHeight: 740)
    }

    @ViewBuilder private var sectionContent: some View {
        switch selection ?? .main {
        case .main: general
        case .keys: Form { Section("Клавиши") { keyControls } }.formStyle(.grouped).controlSize(.small)
        case .exceptions: exceptions
        case .snippets: rules
        case .diagnostics: lab
        }
    }

    @ViewBuilder private var safetyNotice: some View {
        if !store.settingsStorageAvailable || !store.trusted || !store.listening || store.secure || store.recoveryRequired || store.textReviewRequired || store.pendingInput > 0 || store.outstandingInput > 0 || store.bufferedEvents > 0 {
            VStack(alignment: .leading, spacing: 8) {
                if !store.settingsStorageAvailable {
                    Label("Не удалось прочитать настройки", systemImage: "exclamationmark.triangle")
                    Text("Обработка и изменение настроек остановлены; исходные данные сохранены. Восстановите настройки из резервной копии и перезапустите приложение.").font(.caption)
                }
                if !store.trusted || !store.listening {
                    Label(!store.trusted ? "Нужен Универсальный доступ" : "Нужен Мониторинг ввода", systemImage: "hand.raised")
                    Text("Разрешите доступ в Системных настройках. Подключение проверяется автоматически.").font(.caption)
                    Button("Разрешить доступ") { keyboard.requestPermission() }.buttonStyle(.borderedProminent)
                }
                if store.secure {
                    Label("Защищённый ввод включён" + (store.secureInputOwner.map { " — его включило «\($0)»" } ?? ""), systemImage: "lock")
                    Text("Исправления приостановлены, пока он не выключится. Обычно его включают поле пароля, менеджер паролей или «Защищённая клавиатура» в Terminal.").font(.caption)
                }
                if store.textReviewRequired {
                    Label("Результат последней операции не подтверждён", systemImage: "exclamationmark.triangle")
                    Text("Проверьте последнее изменённое поле. Повторная отправка не выполняется. Неподтверждённых событий: \(store.uncertainInput). Обработка приостановлена.").font(.caption)
                    Button("Текст проверен — продолжить") { keyboard.confirmTextReviewed() }
                        .buttonStyle(.borderedProminent).disabled(store.outstandingInput > 0)
                }
                if store.pendingInput > 0 {
                    Text("Сохранено нажатий: \(store.pendingInput). Новый ввод проходит в активное окно. Для восстановления вернитесь в исходное поле и нажмите ⌘⌥R; текст и каретка должны совпадать.").font(.caption)
                    Button("Отбросить сохранённые нажатия…", role: .destructive) { keyboard.discardPendingInput() }
                }
                if store.bufferedEvents > 0 { Text("Сохранено нажатий во время исправлений: \(store.bufferedEvents)").font(.caption) }
                if store.outstandingInput > 0 { Text("Ожидается подтверждение доставки: \(store.outstandingInput)").font(.caption) }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.25)))
            .padding(.horizontal, 20).padding(.bottom, 8).accessibilityElement(children: .contain)
        }
    }
    @ViewBuilder private var correctionControls: some View {
        Toggle("Пауза всех автоисправлений", isOn: $store.settings.paused)
        Toggle("Автоматически исправлять раскладку RU/EN", isOn: $store.settings.automatic)
        Toggle("Исправлять во всех приложениях", isOn: $store.universalInput)
        Toggle("Раннее исправление раскладки (экспериментально)", isOn: $store.earlyCorrection)
        if store.earlyCorrection { Text("Исправляет известные начала слов до пробела. Неизвестные имена и незавершённые адреса могут распознаваться неточно.").font(.caption).foregroundStyle(.secondary) }
        Toggle("Исправлять известные опечатки", isOn: $store.settings.typos)
        Toggle("Восстанавливать «ё» в однозначных словах", isOn: $store.settings.yo)
        Toggle("Расширять словарь средствами macOS", isOn: $store.useSystemDictionary)
    }
    @ViewBuilder private var correctionExplanation: some View {
        if !store.universalInput { Text("Исправления выполняются только в TextEdit, Chrome и Codex, а в Terminal и Ghostty — через интеграцию с zsh.").font(.caption).foregroundStyle(.secondary) }
        if store.universalInput { Text("Слово стирается и набирается заново. Где текст поля доступен, он сверяется перед правкой. Выделение, недоступное через Универсальный доступ, копируется через буфер обмена; его прежнее содержимое возвращается.").font(.caption).foregroundStyle(.secondary) }
    }
    @ViewBuilder private var keyControls: some View {
        HStack {
            Text("Текущая раскладка")
            Spacer()
            Button("ABC") { _ = InputSources.select(.english); keyboard.refresh() }
            Button("Русская") { _ = InputSources.select(.russian); keyboard.refresh() }
        }
        Toggle("Одиночный Shift — сменить раскладку", isOn: $store.settings.singleShift)
        Text("Двойной Shift или ⌘⌥Space — преобразовать слово или выделение. ⌘⌥Z — отменить и запомнить исключение.")
            .font(.caption).foregroundStyle(.secondary)
        Toggle("Одиночный Option — преобразовать слово или выделение", isOn: $store.settings.optionCorrection)
        Toggle("Левый + правый Shift — пауза автоисправлений", isOn: $store.settings.shiftChordPause)
        Toggle("⌘⇧V — вставить текст без форматирования (экспериментально)", isOn: $store.settings.plainPaste)
    }
    @ViewBuilder private var soundControls: some View {
        Toggle("Звук при исправлении", isOn: $store.settings.sound)
        HStack {
            Text(store.customSoundPath.isEmpty ? "Стандартный звук" : "Собственный звук")
            Spacer()
            Button("Выбрать звук…") { store.chooseSound() }
            if !store.customSoundPath.isEmpty { Button("Стандартный") { store.customSoundPath = "" } }
        }
    }
    @ViewBuilder private var startupControl: some View {
        Toggle("Запускать при входе в систему", isOn: Binding(get: {
            store.launchAtLogin
        }, set: { enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                store.launchAtLogin = SMAppService.mainApp.status == .enabled
                store.lastStatus = SMAppService.mainApp.status == .requiresApproval ? "Подтвердите автозапуск в Системных настройках" : "Настройка автозапуска сохранена"
            } catch { store.lastStatus = "Не удалось изменить автозапуск: \(error.localizedDescription)" }
        }))
    }
    private var general: some View {
        Form {
            Section("Исправление текста") { correctionControls }
            Section("Звук") { soundControls }
            Section("Приложение") { startupControl }
            Section { DisclosureGroup("Как выполняется исправление") { correctionExplanation } }
        }.formStyle(.grouped).controlSize(.small)
    }
    private var exceptions: some View {
        Form {
            Section("Слова, которые не нужно исправлять") {
                HStack {
                    TextField("Слово", text: $form.word).onSubmit(addWord)
                    Button("Добавить", systemImage: "plus", action: addWord).labelStyle(.iconOnly)
                        .help("Добавить слово").accessibilityLabel("Добавить слово")
                        .disabled(form.word.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                List(store.settings.excludedWords, id: \.self, selection: $form.selectedWord) { value in
                    Text(value).tag(value)
                }.frame(height: 100).overlay {
                    if store.settings.excludedWords.isEmpty { Text("Нет исключений для слов").foregroundStyle(.secondary) }
                }.accessibilityLabel("Исключённые слова")
                Button("Убрать", systemImage: "minus") {
                    guard let value = form.selectedWord else { return }
                    store.settings.excludedWords.removeAll { $0 == value }; form.selectedWord = nil
                }.labelStyle(.iconOnly).help("Убрать выбранное слово").accessibilityLabel("Убрать выбранное слово")
                    .disabled(form.selectedWord == nil)
            }
            Section("Программы без обработки клавиатуры") {
                HStack {
                    TextField("Идентификатор программы, например com.apple.Terminal", text: $form.bundleID)
                        .onSubmit { addApp(form.bundleID) }
                    Button("Добавить", systemImage: "plus") { addApp(form.bundleID) }.labelStyle(.iconOnly)
                        .help("Добавить приложение").accessibilityLabel("Добавить приложение").disabled(form.bundleID.isEmpty)
                    Button("Выбрать…", action: chooseApp)
                }
                List(store.settings.excludedApps, id: \.self, selection: $form.selectedApp) { value in
                    Text(value).tag(value)
                }.frame(height: 90).overlay {
                    if store.settings.excludedApps.isEmpty { Text("Нет исключённых приложений").foregroundStyle(.secondary) }
                }.accessibilityLabel("Программы без обработки")
                Button("Убрать", systemImage: "minus") {
                    guard let value = form.selectedApp else { return }
                    store.settings.excludedApps.removeAll { $0 == value }; form.selectedApp = nil
                }.labelStyle(.iconOnly).help("Убрать выбранное приложение").accessibilityLabel("Убрать выбранное приложение")
                    .disabled(form.selectedApp == nil)
            }
            Section("Автоисправления в программах") {
                Text("«Выключено» отключает все автоматические изменения в программе: раскладку, опечатки, «ё», регистр и правила. Ручное преобразование работает. Общая пауза и полный запрет обработки имеют приоритет.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField("Идентификатор программы для автоисправлений", text: $form.autoBundleID)
                        .onSubmit { addAutoApp(form.autoBundleID) }
                    Button("Добавить правило", systemImage: "plus") { addAutoApp(form.autoBundleID) }.labelStyle(.iconOnly)
                        .help("Добавить правило").accessibilityLabel("Добавить правило")
                        .disabled(form.autoBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Выбрать программу…", action: chooseAutoApp)
                }
                List(store.settings.appAutomatic.keys.sorted(), id: \.self, selection: $form.selectedAutoApp) { id in
                    HStack {
                        Text(id).textSelection(.enabled)
                        Spacer()
                        Picker("Автоисправления", selection: Binding(get: { store.settings.appAutomatic[id] ?? true },
                            set: { store.settings.appAutomatic[id] = $0 })) {
                            Text("Выключено").tag(false); Text("Включено").tag(true)
                        }.frame(width: 220).accessibilityLabel("Автоисправления в " + id)
                    }.tag(id)
                }.frame(height: 90).overlay {
                    if store.settings.appAutomatic.isEmpty { Text("Нет отдельных правил для программ").foregroundStyle(.secondary) }
                }.accessibilityLabel("Правила автоисправлений в программах")
                Button("Убрать правило", systemImage: "minus") {
                    guard let id = form.selectedAutoApp else { return }
                    store.settings.appAutomatic.removeValue(forKey: id); form.selectedAutoApp = nil
                }.labelStyle(.iconOnly).help("Убрать выбранное правило").accessibilityLabel("Убрать выбранное правило")
                    .disabled(form.selectedAutoApp == nil)
            }
            Section {
                Text("В защищённых полях обработка всегда отключена. В неподдерживаемых редакторах замена пропускается.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).controlSize(.small)
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 16) {
            SnippetsTab(store: store).frame(minHeight: 220)
            GroupBox("Исключения после отмены") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Автоматически изменённое слово можно вернуть через ⌘⌥Z. После этого оно больше не меняется автоматически.")
                        .font(.caption).foregroundStyle(.secondary)
                    List(store.settings.learnedWords, id: \.self, selection: $form.selectedLearnedWord) { value in
                        Text(value).tag(value)
                    }.frame(height: 70).overlay {
                        if store.settings.learnedWords.isEmpty { Text("Нет исключений после отмены").foregroundStyle(.secondary) }
                    }.accessibilityLabel("Исключения после отмены")
                    Button("Снова исправлять", systemImage: "minus") {
                        guard let value = form.selectedLearnedWord else { return }
                        store.settings.learnedWords.removeAll { $0 == value }; form.selectedLearnedWord = nil
                    }.help("Снова исправлять выбранное слово").disabled(form.selectedLearnedWord == nil)
                }.padding(8)
            }
        }.padding(20).controlSize(.small)
    }
    private var lab: some View {
        Form {
            Section("Проверить преобразование") {
                Text("Это предварительный просмотр. Проверка ввода в других программах выполняется отдельно.")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Текст для проверки", text: $form.sample).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Преобразовать раскладку") { form.preview = Layout.convert(form.sample, mapping: InputSources.mapping) }
                    Button("Проверить автоматическое правило") {
                        form.preview = keyboard.decide(form.sample)?.replacement ?? "Без изменения"
                    }
                }
                Text(form.preview.isEmpty ? "Результат появится здесь" : form.preview).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section("Подключение") {
                LabeledContent("Раскладка", value: store.inputSource)
                LabeledContent("Универсальный доступ", value: store.trusted ? "Разрешён" : "Не разрешён")
                LabeledContent("Мониторинг ввода", value: store.listening ? "Разрешён" : "Не разрешён")
                LabeledContent("Отправка клавиш", value: store.posting ? "Разрешена" : "Не разрешена")
                LabeledContent("Обработчик клавиатуры", value: store.tapActive ? "Подключён" : "Не подключён")
                LabeledContent("Последний отказ поля", value: store.lastContextFailure)
            }
            Section("Статистика") {
                LabeledContent("Исправления", value: "\(store.corrected)")
                statisticsSummary
            }
            Section("Диагностика") {
                LabeledContent("Пропущенные операции", value: "\(store.skipped)")
                LabeledContent("События клавиатуры в текущем сеансе", value: "\(store.keyEvents)")
                Text("На этом Mac сохраняются только технические состояния и последние сбои (до трёх отчётов). Текст, сами нажатия и буфер обмена не записываются. Отчёты никуда не отправляются.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Обновить состояние") { keyboard.refresh() }
                    Button("Повторить подключение") { keyboard.retryConnection() }
                    Button("Сохранить отчёт…") { keyboard.saveDiagnosticReport() }
                }
            }
        }.formStyle(.grouped).controlSize(.small)
    }
    private var statisticsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Помощь при вводе").font(.headline)
            statisticsRow("Автоматическая раскладка", category: .automatic)
            statisticsRow("Исправления опечаток", category: .typo)
            statisticsRow("Буква ё", category: .yo)
            statisticsRow("Ручные исправления", category: .manual)
            statisticsRow("Переключения по Shift", category: .singleShift)
            LabeledContent("Примерная экономия", value: UsageStatistics.durationLabel(seconds: store.statistics.estimatedSeconds))
            Text("Оценка на действие: раскладка и опечатка — 10 с, ё — 3 с, ручное исправление — 7 с, Shift — 2 с, звук — 1 с. Это приблизительная оценка, а не измеренное время.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Звуков воспроизведено: \(store.statistics[.sound])")
                .font(.caption).foregroundStyle(.secondary)
            if store.statistics.unclassifiedHistorical > 0 {
                Text("Исправления из прежней версии: \(store.statistics.unclassifiedHistorical). Они сохранены отдельно и не входят в оценку времени.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !store.statisticsStorageAvailable {
                Text("Прежняя статистика сохранена, но недоступна для обновления. Новые показатели видны до закрытия приложения; общий итог исправлений продолжает сохраняться.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func statisticsRow(_ label: String, category: UsageCategory) -> some View {
        LabeledContent(label, value: "\(store.statistics[category]) · ≈ \(UsageStatistics.durationLabel(seconds: store.statistics.estimatedSeconds(for: category)))")
    }
    private func addWord() {
        let value = form.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty, !store.settings.excludedWords.contains(value) else { return }
        store.settings.excludedWords.append(value); form.word = ""
    }
    private func addApp(_ id: String) {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !store.settings.excludedApps.contains(value) else { return }
        store.settings.excludedApps.append(value); form.bundleID = ""
    }
    private func addAutoApp(_ id: String) {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }) else { return }
        if store.settings.appAutomatic[value] == nil { store.settings.appAutomatic[value] = false }
        form.autoBundleID = ""
    }
    private func chooseAutoApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { addAutoApp(id) }
    }
    private func chooseApp() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { addApp(id) }
    }
}

final class SettingsForm: ObservableObject {
    @Published var word = ""
    @Published var bundleID = ""
    @Published var autoBundleID = ""
    @Published var sample = "ghbdtn"
    @Published var preview = ""
    @Published var selectedWord: String?
    @Published var selectedApp: String?
    @Published var selectedAutoApp: String?
    @Published var selectedLearnedWord: String?
}
