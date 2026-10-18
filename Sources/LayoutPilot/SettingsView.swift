import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import LayoutPilotCore

/// Independent palette for LayoutPilot; no original artwork or color tables.
private enum HeaderPalette: String, CaseIterable, Identifiable {
    case blue, green, violet, orange, neutral
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blue: return "Синий"
        case .green: return "Зелёный"
        case .violet: return "Фиолетовый"
        case .orange: return "Оранжевый"
        case .neutral: return "Нейтральный"
        }
    }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .violet: return .purple
        case .orange: return .orange
        case .neutral: return .gray
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    let keyboard: KeyboardService
    @ObservedObject private var form = SettingsForm()
    @AppStorage("theme") private var theme = "system"
    @AppStorage("headerColor") private var headerColorName = HeaderPalette.blue.rawValue
    @AppStorage("headerLightText") private var headerLightText = true
    private var headerPalette: Binding<HeaderPalette> {
        Binding(get: { HeaderPalette(rawValue: headerColorName) ?? .blue },
                set: { headerColorName = $0.rawValue })
    }
    private var headerColor: Color { (HeaderPalette(rawValue: headerColorName) ?? .blue).color }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.badge.ellipsis").font(.system(size: 34)).foregroundStyle(headerLightText ? Color.white : Color.black)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TypeTune").font(.title2.bold()).foregroundStyle(headerLightText ? Color.white : Color.black)
                    Text("Чтобы мысли не спотыкались о клавиши").foregroundStyle((headerLightText ? Color.white : Color.black).opacity(0.85))
                }
                Spacer()
                Label(store.serviceStatus.title, systemImage: store.running && !store.recoveryRequired ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(store.running && !store.recoveryRequired ? .green : .orange)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.background, in: Capsule())
            }.padding(22).background {
                ZStack {
                    headerColor.opacity(0.85)
                    if let image = store.headerImage { Image(nsImage: image).resizable().scaledToFill() }
                }
            }.clipped()
            .overlay(alignment: .bottom) {
                if form.headerDropTargeted { Rectangle().fill(Color.accentColor).frame(height: 3) }
            }
            .onDrop(of: [.fileURL, .tiff], isTargeted: $form.headerDropTargeted, perform: acceptHeaderImage)
            Divider()
            if !store.trusted || !store.listening {
                HStack {
                    VStack(alignment: .leading) {
                        Text(!store.trusted ? "Нужен Универсальный доступ" : "Нужен Мониторинг ввода").font(.headline)
                        Text("Разрешите доступ в Системных настройках. Подключение проверяется автоматически.").font(.caption)
                    }
                    Spacer()
                    Button("Разрешить доступ") { keyboard.requestPermission() }.buttonStyle(.borderedProminent)
                }.padding().background(.orange.opacity(0.10))
            }
            if !store.settingsStorageAvailable {
                Text("Не удалось прочитать настройки. Обработка и изменение настроек остановлены; исходные данные сохранены. Восстановите настройки из резервной копии и перезапустите приложение.")
                    .font(.caption).padding(10).background(.orange.opacity(0.10))
            }
            if store.secure {
                Label("Защищённый ввод включён. Исправления приостановлены.", systemImage: "lock.fill").padding(10)
            }
            if store.bufferedEvents > 0 {
                Text("Сохранено нажатий во время исправлений: \(store.bufferedEvents)").font(.caption).padding(4)
            }
            if store.recoveryRequired || store.outstandingInput > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    if store.textReviewRequired {
                        Text("Результат последней операции не подтверждён. Проверьте последнее изменённое поле. Повторная отправка не выполняется.").font(.caption)
                        if store.uncertainInput > 0 { Text("Неподтверждённых событий: \(store.uncertainInput)").font(.caption) }
                        Button("Текст проверен — продолжить") { keyboard.confirmTextReviewed() }
                            .disabled(store.outstandingInput > 0)
                    }
                    if store.pendingInput > 0 {
                        Text("Сохранено нажатий: \(store.pendingInput). Новый ввод проходит в активное окно. Для восстановления вернитесь в исходное поле и нажмите ⌘⌥R; текст и каретка должны совпадать.").font(.caption)
                        Button("Отбросить сохранённые нажатия…") { keyboard.discardPendingInput() }
                    }
                    if store.outstandingInput > 0 { Text("Ожидается подтверждение доставки: \(store.outstandingInput)").font(.caption) }
                }.padding(10)
            }
            TabView(selection: $form.tab) {
                general.tabItem { Label("Основное", systemImage: "keyboard") }.tag(0)
                exceptions.tabItem { Label("Исключения", systemImage: "hand.raised") }.tag(1)
                rules.tabItem { Label("Правила", systemImage: "text.badge.plus") }.tag(2)
                lab.tabItem { Label("Проверка", systemImage: "checkmark.circle") }.tag(3)
            }.padding(.horizontal, 16).padding(.top, 12).disabled(!store.settingsStorageAvailable)
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.serviceStatus.message).font(.caption).lineLimit(2)
                    Text("Последнее событие: " + store.lastStatus).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · экспериментальная").font(.caption2).foregroundStyle(.secondary)
                Button("Выйти") { NSApp.terminate(nil) }.font(.caption)
            }.padding(14)
        }
        .frame(width: 740, height: 690)
        .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
    }
    private var general: some View {
        Form {
            Section("Исправление текста") {
                Toggle("Пауза всех автоисправлений", isOn: $store.settings.paused)
                Toggle("Автоматически исправлять раскладку RU/EN", isOn: $store.settings.automatic)
                Toggle("Исправлять во всех приложениях", isOn: $store.universalInput)
                if !store.universalInput { Text("Исправления выполняются только в TextEdit, Chrome и Codex, а в Terminal и Ghostty — через интеграцию с zsh.").font(.caption).foregroundStyle(.secondary) }
                if store.universalInput { Text("Слово стирается и набирается заново. Где текст поля доступен, он сверяется перед правкой. Выделение, недоступное через Универсальный доступ, копируется через буфер обмена; его прежнее содержимое возвращается.").font(.caption).foregroundStyle(.secondary) }
                Toggle("Раннее исправление раскладки (экспериментально)", isOn: $store.earlyCorrection)
                if store.earlyCorrection { Text("Исправляет известные начала слов до пробела. Неизвестные имена и незавершённые адреса могут распознаваться неточно.").font(.caption).foregroundStyle(.secondary) }
                Toggle("Исправлять известные опечатки", isOn: $store.settings.typos)
                Toggle("Восстанавливать «ё» в однозначных словах", isOn: $store.settings.yo)
                Toggle("Расширять словарь средствами macOS", isOn: $store.useSystemDictionary)
                Toggle("Звук при исправлении", isOn: $store.settings.sound)
                HStack {
                    Text(store.customSoundPath.isEmpty ? "Стандартный звук" : "Собственный звук")
                    Spacer()
                    Button("Выбрать звук…") { store.chooseSound() }
                    if !store.customSoundPath.isEmpty { Button("Стандартный") { store.customSoundPath = "" } }
                }
            }
            Section("Клавиши") {
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
            Section("Приложение") {
                Toggle("Запускать при входе в систему", isOn: Binding(get: {
                    store.launchAtLogin
                }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        store.launchAtLogin = SMAppService.mainApp.status == .enabled
                        store.lastStatus = SMAppService.mainApp.status == .requiresApproval ? "Подтвердите автозапуск в Системных настройках" : "Настройка автозапуска сохранена"
                    } catch { store.lastStatus = "Не удалось изменить автозапуск: \(error.localizedDescription)" }
                }))
                Picker("Оформление", selection: $theme) {
                    Text("Как в системе").tag("system"); Text("Светлое").tag("light"); Text("Тёмное").tag("dark")
                }
                Picker("Цвет заголовка", selection: headerPalette) {
                    ForEach(HeaderPalette.allCases) { value in Text(value.title).tag(value) }
                }
                Toggle("Светлая надпись заголовка", isOn: $headerLightText)
                HStack {
                    Text(store.headerImage != nil ? "Изображение заголовка" :
                        (store.headerImagePath.isEmpty ? "Однотонный фон" : "Изображение недоступно"))
                    Spacer()
                    Button("Выбрать изображение…") { store.chooseHeaderImage() }
                    if !store.headerImagePath.isEmpty { Button("Убрать изображение") { store.resetHeaderImage() } }
                }
            }
        }.formStyle(.grouped)
    }
    private var exceptions: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("Слова, которые не нужно исправлять").font(.headline)
            HStack {
                TextField("Слово", text: $form.word).onSubmit(addWord)
                Button("Добавить", action: addWord).disabled(form.word.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            List {
                ForEach(store.settings.excludedWords, id: \.self) { value in
                    HStack { Text(value); Spacer(); Button("Убрать") { store.settings.excludedWords.removeAll { $0 == value } } }.accessibilityElement(children: .contain)
                }
            }.frame(height: 120)
            Text("Программы без обработки клавиатуры").font(.headline)
            HStack {
                TextField("Идентификатор программы, например com.apple.Terminal", text: $form.bundleID)
                Button("Добавить") { addApp(form.bundleID) }.disabled(form.bundleID.isEmpty)
                Button("Выбрать…", action: chooseApp)
            }
            List {
                ForEach(store.settings.excludedApps, id: \.self) { value in
                    HStack { Text(value); Spacer(); Button("Убрать") { store.settings.excludedApps.removeAll { $0 == value } } }.accessibilityElement(children: .contain)
                }
            }.frame(height: 90)
            Text("Автоисправления в программах").font(.headline)
            Text("«Выключено» отключает все автоматические изменения в программе: раскладку, опечатки, «ё», регистр и правила. Ручное преобразование работает. Общая пауза и полный запрет обработки имеют приоритет.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("Идентификатор программы для автоисправлений", text: $form.autoBundleID)
                Button("Добавить правило") { addAutoApp(form.autoBundleID) }.disabled(form.autoBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Выбрать программу…", action: chooseAutoApp)
            }
            ForEach(store.settings.appAutomatic.keys.sorted(), id: \.self) { id in
                HStack {
                    Text(id).textSelection(.enabled)
                    Spacer()
                    Picker("Автоисправления", selection: Binding(get: { store.settings.appAutomatic[id] ?? true },
                        set: { store.settings.appAutomatic[id] = $0 })) {
                        Text("Выключено").tag(false)
                        Text("Включено").tag(true)
                    }.frame(width: 245)
                    Button("Убрать правило") { store.settings.appAutomatic.removeValue(forKey: id) }
                }.accessibilityElement(children: .contain)
            }
            Text("В защищённых полях обработка всегда отключена. В неподдерживаемых редакторах замена пропускается.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18)
        }
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Собственные замены").font(.headline)
            Text("Правило применяется к целому слову после разделителя. Исключения имеют приоритет.").foregroundStyle(.secondary)
            HStack {
                TextField("Исходное слово", text: $form.ruleSource)
                Image(systemName: "arrow.right")
                TextField("Заменить на", text: $form.ruleTarget)
                Button("Добавить") {
                    store.addRule(form.ruleSource, form.ruleTarget); form.ruleSource = ""; form.ruleTarget = ""
                }.disabled(form.ruleSource.isEmpty || form.ruleTarget.isEmpty)
            }
            List {
                ForEach(store.settings.rules) { rule in
                    HStack {
                        Text(rule.source); Image(systemName: "arrow.right"); Text(rule.replacement)
                        Spacer(); Button("Убрать") { store.settings.rules.removeAll { $0.id == rule.id } }
                    }.accessibilityElement(children: .contain)
                }
            }
            Text("Исключения после отмены").font(.headline)
            Text("Автоматически изменённое слово можно вернуть через ⌘⌥Z. После этого оно больше не меняется автоматически.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(store.settings.learnedWords, id: \.self) { value in
                        HStack { Text(value); Spacer(); Button("Снова исправлять") { store.settings.learnedWords.removeAll { $0 == value } } }
                    }
                }
            }.frame(height: 100)
        }.padding(18)
    }
    private var lab: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("Проверить преобразование").font(.headline)
            Text("Это предварительный просмотр. Проверка ввода в других программах выполняется отдельно.").foregroundStyle(.secondary)
            TextField("Текст для проверки", text: $form.sample)
            HStack {
                Button("Преобразовать раскладку") { form.preview = Layout.convert(form.sample, mapping: InputSources.mapping) }
                Button("Проверить автоматическое правило") {
                    form.preview = keyboard.decide(form.sample)?.replacement ?? "Без изменения"
                }
            }
            Text(form.preview.isEmpty ? "Результат появится здесь" : form.preview).font(.title3).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            Divider()
            LabeledContent("Раскладка", value: store.inputSource)
            LabeledContent("Универсальный доступ", value: store.trusted ? "Разрешён" : "Не разрешён")
            LabeledContent("Мониторинг ввода", value: store.listening ? "Разрешён" : "Не разрешён")
            LabeledContent("Отправка клавиш", value: store.posting ? "Разрешена" : "Не разрешена")
            LabeledContent("Обработчик клавиатуры", value: store.tapActive ? "Подключён" : "Не подключён")
            LabeledContent("Последний отказ поля", value: store.lastContextFailure)
            LabeledContent("Исправления", value: "\(store.corrected)")
            statisticsSummary
            LabeledContent("Пропущенные операции", value: "\(store.skipped)")
            LabeledContent("События клавиатуры в текущем сеансе", value: "\(store.keyEvents)")
            Text("На этом Mac сохраняются только технические состояния и последние сбои (до трёх отчётов). Текст, сами нажатия и буфер обмена не записываются. Отчёты никуда не отправляются.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            HStack {
                Button("Обновить состояние") { keyboard.refresh() }
                Button("Повторить подключение") { keyboard.retryConnection() }
                Button("Сохранить отчёт…") { keyboard.saveDiagnosticReport() }
            }
        }.padding(18)
        }
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
    private func acceptHeaderImage(_ providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.canLoadObject(ofClass: NSURL.self) }) {
            provider.loadObject(ofClass: NSURL.self) { value, _ in
                let url = value as? URL
                DispatchQueue.main.async {
                    if let url { store.importHeaderImage(from: url) }
                    else { store.lastStatus = "Не удалось прочитать изображение" }
                }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.tiff.identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.tiff.identifier) { data, _ in
                DispatchQueue.main.async {
                    if let data { store.importHeaderImage(data: data) }
                    else { store.lastStatus = "Не удалось прочитать изображение" }
                }
            }
            return true
        }
        return false
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
    @Published var ruleSource = ""
    @Published var ruleTarget = ""
    @Published var sample = "ghbdtn"
    @Published var preview = ""
    @Published var tab = 0
    @Published var headerDropTargeted = false
}
