import AppKit
import LayoutPilotCore
import SwiftUI
import UniformTypeIdentifiers

/// The «Сниппеты» settings tab (docs/SNIPPETS_PLAN.md, S7): list, search, add/edit, enable,
/// delete, import and export.
struct SnippetsTab: View {
    @ObservedObject var store: Store
    @State private var query = ""
    @State private var editing: Snippet?
    @State private var deleting: Snippet?
    @State private var selection: UUID?

    private var filtered: [Snippet] {
        let all = store.snippets.snippets
        guard !query.isEmpty else { return all }
        return all.filter { $0.abbreviation.localizedCaseInsensitiveContains(query) || $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("Сниппеты", isOn: $store.snippetsEnabled)
                Spacer()
                Button("Импорт…") { importFile() }.disabled(!store.snippetsStorageAvailable)
                Button("Экспорт…") { exportFile() }.disabled(store.snippets.snippets.isEmpty)
            }
            Text("Сокращение заменяется текстом во всех приложениях. Со знаком в начале (;адр) — сразу, словом (спс) — после пробела. Срабатывает и в другой раскладке. ⌘⌥Z сразу после вставки возвращает сокращение.")
                .font(.caption).foregroundStyle(.secondary)
            if !store.snippetsStorageAvailable {
                Text("Файл сниппетов недоступен — изменения не сохраняются, чтобы его не перезаписать.").font(.caption).foregroundStyle(.red)
            }
            if !store.universalInput {
                Text("Сниппеты работают с включённым «Исправлять во всех приложениях». Без него действуют только простые замены целых слов.")
                    .font(.caption).foregroundStyle(.orange)
            }
            TextField("Поиск по сокращению и тексту", text: $query)
            List(filtered, selection: $selection) { snippet in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(get: { snippet.enabled }, set: { store.setSnippet(snippet.id, enabled: $0) }))
                        .labelsHidden().accessibilityLabel("Включить сниппет " + snippet.abbreviation)
                        .disabled(!store.snippetsStorageAvailable)
                    Text(snippet.abbreviation).font(.body.monospaced())
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(Self.summary(snippet.text)).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Text(snippet.trigger == .immediate ? "сразу" : "по пробелу").font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .contain).tag(snippet.id)
            }.listStyle(.inset).accessibilityLabel("Сниппеты")
            .overlay {
                if filtered.isEmpty {
                    VStack(spacing: 4) {
                        Text(query.isEmpty ? "Нет сниппетов" : "Ничего не найдено").font(.headline)
                        Text(query.isEmpty ? "Добавьте сокращение кнопкой «+»." : "Измените поисковый запрос.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.allowsHitTesting(false)
                }
            }
            HStack(spacing: 8) {
                Button("Добавить", systemImage: "plus") { editing = Snippet(abbreviation: "", text: "") }
                    .labelStyle(.iconOnly).help("Добавить сниппет").accessibilityLabel("Добавить сниппет")
                    .disabled(!store.snippetsStorageAvailable)
                Button("Изменить", systemImage: "pencil") { editing = selectedSnippet }
                    .labelStyle(.iconOnly).help("Изменить сниппет").accessibilityLabel("Изменить сниппет")
                    .disabled(!store.snippetsStorageAvailable || selectedSnippet == nil)
                Button("Удалить", systemImage: "minus") { deleting = selectedSnippet }
                    .labelStyle(.iconOnly).help("Удалить сниппет").accessibilityLabel("Удалить сниппет")
                    .disabled(!store.snippetsStorageAvailable || selectedSnippet == nil)
                Spacer()
                Text("Всего: \(store.snippets.snippets.count)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Сниппеты хранятся на диске без шифрования — не храните в них пароли.").font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { snippet in SnippetEditorSheet(store: store, original: snippet) }
        .alert("Удалить сниппет?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { snippet in
            Button("Удалить", role: .destructive) { store.deleteSnippet(snippet.id) }
            Button("Отмена", role: .cancel) {}
        } message: { snippet in Text(snippet.abbreviation) }
    }

    private var selectedSnippet: Snippet? { filtered.first { $0.id == selection } }

    static func summary(_ text: String) -> String {
        let line = text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let short = line.count > 60 ? String(line.prefix(60)) + "…" : line
        return text.contains("\n") ? short + " ⏎" : short
    }
    private func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { store.importSnippets(from: url) }
    }
    private func exportFile() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "TypeTune-сниппеты.json"
        if panel.runModal() == .OK, let url = panel.url { store.exportSnippets(to: url) }
    }
}

/// Adds or edits one snippet. Saving is refused while the snippet has issues.
struct SnippetEditorSheet: View {
    @ObservedObject var store: Store
    let original: Snippet
    @State private var draft: Snippet
    /// Until the user picks a trigger, it follows the abbreviation (DECISIONS п. 28).
    @State private var triggerChosen: Bool
    @State private var bundleID = ""
    @Environment(\.dismiss) private var dismiss

    init(store: Store, original: Snippet) {
        self.store = store
        self.original = original
        _draft = State(initialValue: original)
        _triggerChosen = State(initialValue: !original.abbreviation.isEmpty)
    }

    private var issues: [SnippetIssue] { store.snippetIssues(draft) }
    private var isNew: Bool { !store.snippets.snippets.contains { $0.id == original.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isNew ? "Новый сниппет" : "Сниппет").font(.headline)
            HStack {
                TextField("Сокращение, например ;адр или спс", text: $draft.abbreviation).font(.body.monospaced())
                Picker("", selection: Binding(get: { draft.trigger }, set: { draft.trigger = $0; triggerChosen = true })) {
                    Text("сразу").tag(Snippet.Trigger.immediate)
                    Text("после пробела").tag(Snippet.Trigger.boundary)
                }.labelsHidden().frame(width: 160)
            }
            .onChange(of: draft.abbreviation) { _, value in
                if !triggerChosen { draft.trigger = Snippet.defaultTrigger(for: value) }
            }
            Text("Текст").font(.subheadline)
            TextEditor(text: $draft.text).font(.body.monospaced()).frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            HStack {
                Text("Вставить:").font(.caption)
                ForEach(["{{дата}}", "{{время}}", "{{буфер}}", "{{курсор}}"], id: \.self) { variable in
                    Button(variable) { draft.text += variable }.font(.caption)
                }
            }
            Text("Формат: {{дата:d MMMM yyyy}}, {{время:HH:mm:ss}}. {{буфер}} — текст из буфера обмена, {{курсор}} — где встанет каретка. Буквальные скобки — \\{{.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Toggle("И в другой раскладке", isOn: $draft.otherLayout)
                Toggle("Переносить регистр", isOn: $draft.matchCase)
                Toggle("Включён", isOn: $draft.enabled)
            }
            Picker("Приложения", selection: $draft.applications.mode) {
                Text("все").tag(ApplicationFilter.Mode.all)
                Text("только выбранные").tag(ApplicationFilter.Mode.only)
                Text("кроме выбранных").tag(ApplicationFilter.Mode.except)
            }.pickerStyle(.segmented)
            if draft.applications.mode != .all {
                ForEach(draft.applications.applications, id: \.self) { id in
                    HStack { Text(id).font(.caption.monospaced()); Spacer()
                        Button("Убрать") { draft.applications.applications.removeAll { $0 == id } }.font(.caption) }
                }
                HStack {
                    TextField("Bundle ID", text: $bundleID)
                    Button("Добавить") { addApplication(bundleID) }.disabled(bundleID.isEmpty)
                    Button("Выбрать приложение…") { chooseApplication() }
                }
            }
            Text("Предпросмотр: " + preview).font(.caption).lineLimit(3)
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                Text(message).font(.caption).foregroundStyle(.red)
            }
            if draft.trigger == .immediate, draft.abbreviation.first.map({ $0.isLetter || $0.isNumber }) == true {
                Text("Сокращение похоже на слово и сработает сразу после набора, даже внутри обычного текста.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { if store.saveSnippet(draft).isEmpty { dismiss() } }
                    .keyboardShortcut(.defaultAction).disabled(!issues.isEmpty)
            }
        }
        .padding(18).frame(width: 600)
    }

    private var preview: String {
        switch SnippetTemplate.render(draft.text, now: Date(), timeZone: .current, clipboard: "‹буфер›") {
        case .success(let expansion):
            guard let offset = expansion.caretOffset else { return expansion.text }
            var text = expansion.text
            text.insert("▏", at: text.index(text.endIndex, offsetBy: -offset))
            return text
        case .failure: return "—"
        }
    }
    private var messages: [String] {
        issues.map { issue in
            switch issue {
            case .abbreviationLength: return "Сокращение — от 2 до 64 символов"
            case .abbreviationCharacters: return "В сокращении не должно быть пробелов"
            case .emptyText: return "Введите текст сниппета"
            case .textTooLong: return "Текст длиннее 10 000 символов"
            case .textCharacters: return "В тексте недопустимые управляющие символы"
            case .duplicate(let id):
                let other = store.snippets.snippets.first { $0.id == id }?.abbreviation ?? ""
                return "Такое сокращение уже есть: \(other)"
            case .template(let failure):
                switch failure {
                case .unclosed(let at): return "Не закрыта переменная {{ (символ \(at + 1))"
                case .unknownVariable(let name, let at): return "Неизвестная переменная «\(name)» (символ \(at + 1))"
                case .emptyFormat(let at): return "Пустой формат после двоеточия (символ \(at + 1))"
                case .unexpectedFormat(let at): return "У {{буфер}} и {{курсор}} нет формата (символ \(at + 1))"
                case .repeatedCursor(let at): return "{{курсор}} можно указать один раз (символ \(at + 1))"
                }
            }
        }
    }
    private func addApplication(_ id: String) {
        let value = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !draft.applications.applications.contains(value) else { return }
        draft.applications.applications.append(value); bundleID = ""
    }
    private func chooseApplication() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { addApplication(id) }
    }
}
