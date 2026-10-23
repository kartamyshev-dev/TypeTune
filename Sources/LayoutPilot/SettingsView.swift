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
    private let accent = Color(red: 1, green: 0.45, blue: 0.24)
    private let graphite = Color(red: 0.12, green: 0.13, blue: 0.15)

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Text("typetune").font(.system(size: 24, weight: .black, design: .rounded)).tracking(-1)
                    Text("/ ПУЛЬТ НАБОРА").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Label(store.serviceStatus.title, systemImage: store.running && !store.recoveryRequired ? "circle.fill" : "exclamationmark.circle")
                        .font(.caption).foregroundStyle(store.running && !store.recoveryRequired ? accent : .secondary)
                    Button { store.settings.paused.toggle() } label: {
                        Image(systemName: store.settings.paused ? "play.fill" : "pause.fill")
                    }.accessibilityLabel(store.settings.paused ? "Продолжить автоисправления" : "Приостановить автоисправления")
                        .help(store.settings.paused ? "Продолжить автоисправления" : "Приостановить автоисправления")
                        .disabled(!store.settingsStorageAvailable)
                }
                HStack(spacing: 20) {
                    ForEach(SettingsSection.allCases) { section in
                        Button { selection = section } label: {
                            Text(section.title).font(.system(size: 12, weight: selection == section ? .bold : .regular))
                                .foregroundStyle(selection == section ? accent : Color.secondary)
                                .padding(.vertical, 5)
                        }.buttonStyle(.plain).accessibilityAddTraits(selection == section ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }.accessibilityLabel("Разделы настроек")
            }.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 12)
            if needsSafetyNotice {
                ScrollView { safetyNotice }.frame(height: 150)
            }
            sectionContent
                .disabled(!store.settingsStorageAvailable)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity).clipped()
            Divider().padding(.horizontal, 26)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.serviceStatus.message).font(.system(size: 10)).lineLimit(2)
                    Text("Последнее событие: " + store.lastStatus).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }.help(store.serviceStatus.message + "\n" + store.lastStatus)
                Spacer(minLength: 6)
                Menu {
                    Button("Сохранить отчёт…") { keyboard.saveDiagnosticReport() }
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · экспериментальная")
                    Button("Выйти из TypeTune") { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().help("Отчёт, версия и выход")
                .accessibilityLabel("Отчёт, версия и выход")
            }.padding(.horizontal, 26).padding(.vertical, 10)
        }
        .frame(minWidth: 760, idealWidth: 760, minHeight: 560, idealHeight: 560)
        .background(graphite).tint(accent).environment(\.colorScheme, .dark).preferredColorScheme(.dark)
        .toggleStyle(.switch).controlSize(.small)
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

    private var needsSafetyNotice: Bool { !store.settingsStorageAvailable || !store.trusted || !store.listening || store.secure || store.recoveryRequired || store.textReviewRequired || store.pendingInput > 0 || store.outstandingInput > 0 || store.bufferedEvents > 0 }

    @ViewBuilder private var safetyNotice: some View {
        if needsSafetyNotice {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) {
                        panelHeading("01 / РАСКЛАДКА")
                        HStack(spacing: 9) {
                            keycap("A", color: .primary)
                            Text("↔").font(.title2).foregroundStyle(accent)
                            keycap("Я", color: accent)
                        }.accessibilityHidden(true)
                        Text("RU / EN").font(.system(size: 12, weight: .medium, design: .monospaced))
                        Text("ghbdtn → привет").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        panelToggle("Исправлять раскладку", isOn: $store.settings.automatic).font(.system(size: 11))
                    }.padding(18).frame(width: 260, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 14) {
                        panelHeading("02 / ТОЧНОСТЬ")
                        panelToggle("Опечатки", isOn: $store.settings.typos).help("Исправлять известные опечатки")
                        panelToggle("Буква «ё»", isOn: $store.settings.yo).help("Восстанавливать «ё» в однозначных словах")
                        panelToggle("Словарь macOS", isOn: $store.useSystemDictionary).help("Расширять словарь средствами macOS")
                        Divider()
                        Text("Исправления по словарю. Неизвестные слова остаются без изменений.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 13)).padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                }
                DisclosureGroup("Приложения, звук и автозапуск") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Исправлять во всех приложениях", isOn: $store.universalInput)
                        correctionExplanation
                        Divider()
                        soundControls
                        Divider()
                        startupControl
                    }.padding(.top, 12)
                }
                DisclosureGroup("Дополнительные параметры") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Раннее исправление раскладки (экспериментально)", isOn: $store.earlyCorrection)
                        if store.earlyCorrection {
                            Text("Исправляет известные начала слов до пробела. Неизвестные имена и незавершённые адреса могут распознаваться неточно.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 12)
                }
                Text("Double Shift — исправить · ⌘⌥Z — отменить")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(.horizontal, 26).padding(.vertical, 12)
        }
    }
    private func panelToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }
    private func panelHeading(_ title: String) -> some View {
        Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
    }
    private func keycap(_ title: String, color: Color) -> some View {
        Text(title).font(.system(size: 34, weight: .semibold, design: .rounded))
            .foregroundStyle(color).frame(width: 72, height: 68)
            .background(LinearGradient(colors: [Color.white.opacity(0.09), Color.white.opacity(0.025)],
                                        startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
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
