import AppKit
import Combine
import ImageIO
import ServiceManagement
import UniformTypeIdentifiers
import LayoutPilotCore

final class Store: ObservableObject {
    @Published var settings: Settings { didSet { persist() } }
    @Published private(set) var settingsStorageAvailable = true
    @Published private(set) var corrected: Int
    @Published private(set) var statistics: UsageStatistics
    @Published private(set) var statisticsStorageAvailable = true
    @Published var lastStatus = "Обработка выключена"
    @Published var running = false
    @Published var serviceStatus: InputServiceStatus = .waitingForContext
    @Published var lastContextFailure = "—"
    @Published var posting = false
    @Published var tapActive = false
    @Published var trusted = false
    @Published var listening = false
    @Published var secure = false
    /// The application that turned Secure Input on, when macOS reveals it.
    @Published var secureInputOwner: String?
    @Published var inputSource = "—"
    @Published var launchAtLogin = false
    @Published var bufferedEvents = 0
    let testSelectionDelay: TimeInterval
    @Published var recoveryRequired = false
    @Published var pendingInput = 0
    @Published var outstandingInput = 0
    @Published var uncertainInput = 0
    @Published var textReviewRequired = false
    @Published var skipped = 0
    @Published var keyEvents = 0
    @Published var customSoundPath: String { didSet { defaults.set(customSoundPath, forKey: "customSoundPath") } }
    @Published var useSystemDictionary: Bool { didSet { defaults.set(useSystemDictionary, forKey: "useSystemDictionary") } }
    @Published var earlyCorrection: Bool { didSet { defaults.set(earlyCorrection, forKey: "earlyCorrection") } }
    /// Universal mode: correction in every application by Backspace and retyping, verified
    /// with Accessibility where the field is readable. On unless the user turned it off;
    /// off restores the earlier per-application path (TextEdit, Chrome, Codex, zsh).
    @Published var universalInput: Bool { didSet { defaults.set(universalInput, forKey: "universalInput") } }
    /// Snippets (docs/SNIPPETS_PLAN.md): on by default; they fire in universal mode only.
    @Published var snippetsEnabled: Bool { didSet { defaults.set(snippetsEnabled, forKey: "snippetsEnabled") } }
    @Published private(set) var snippets = SnippetLibrary()
    /// False when snippets.json is unreadable or newer: nothing is written until the user decides.
    @Published private(set) var snippetsStorageAvailable = true
    /// Snippets that can fire, computed once per change rather than on every key.
    private(set) var usableSnippets: [Snippet] = []
    private let snippetsURL: URL?
    @Published private(set) var headerImagePath: String { didSet { defaults.set(headerImagePath, forKey: "headerImagePath") } }
    @Published private(set) var headerImage: NSImage?
    private let defaults: UserDefaults
    private var activeSound: NSSound?
    /// `snippetsURL` defaults to Application Support for the standard defaults; isolated
    /// defaults (probes) get an isolated temporary file, so they never touch the user's snippets.
    init(defaults: UserDefaults = .standard, snippetsURL: URL? = nil) {
        self.defaults = defaults
        testSelectionDelay = Double(max(0, min(150, defaults.integer(forKey: "test.axSelectionDelayMilliseconds")))) / 1000
        useSystemDictionary = defaults.bool(forKey: "useSystemDictionary")
        earlyCorrection = defaults.bool(forKey: "earlyCorrection")
        universalInput = defaults.object(forKey: "universalInput") == nil ? true : defaults.bool(forKey: "universalInput")
        snippetsEnabled = defaults.object(forKey: "snippetsEnabled") == nil ? true : defaults.bool(forKey: "snippetsEnabled")
        if let snippetsURL { self.snippetsURL = snippetsURL }
        else if defaults === UserDefaults.standard {
            self.snippetsURL = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true).appendingPathComponent("LayoutPilot/snippets.json")
        } else {
            self.snippetsURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("typetune-snippets-\(UUID().uuidString).json")
        }
        customSoundPath = defaults.string(forKey: "customSoundPath") ?? ""
        headerImagePath = defaults.string(forKey: "headerImagePath") ?? ""
        headerImage = nil
        if defaults.object(forKey: "settings.v1") == nil {
            settings = Settings()
        } else if let data = defaults.data(forKey: "settings.v1"), let value = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = value
        } else {
            settings = Settings()
            settingsStorageAvailable = false
        }
        let legacy = Self.legacyCorrected(defaults.object(forKey: "corrected"))
        let resolvedStatistics: UsageStatistics
        let storageAvailable: Bool
        if let raw = defaults.object(forKey: "statistics.v1") {
            if let data = raw as? Data, let decoded = try? JSONDecoder().decode(UsageStatistics.self, from: data) {
                var merged = decoded
                merged.reconcileLegacyTotal(legacy)
                resolvedStatistics = merged
                storageAvailable = true
            } else {
                // Preserve the exact malformed value. Never silently replace a
                // saved record with zeros or duplicate unknown data in another key.
                resolvedStatistics = UsageStatistics(legacyCorrected: legacy)
                storageAvailable = false
            }
        } else {
            resolvedStatistics = UsageStatistics(legacyCorrected: legacy)
            storageAvailable = true
        }
        statistics = resolvedStatistics
        corrected = Int(resolvedStatistics.correctedTotal)
        statisticsStorageAvailable = storageAvailable
        if storageAvailable { persistStatistics() }
        else { lastStatus = "Сохранённая статистика недоступна. Прежний итог исправлений сохранён." }
        loadSnippets()
        if !headerImagePath.isEmpty {
            do {
                let selected = URL(fileURLWithPath: headerImagePath)
                let directory = try Self.headerImagesDirectory(create: false).resolvingSymlinksInPath().standardizedFileURL
                guard selected.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent() == directory else {
                    throw HeaderImageError.notOwned
                }
                headerImage = try Self.headerImage(from: Self.readHeaderBytes(selected))
            } catch {
                // Preserve the saved selection for an explicit user reset.
                // A broken/missing copy never authorizes another source path.
                lastStatus = "Изображение шапки недоступно. Выберите другое или сбросьте его."
            }
        }
    }
    private func persist() {
        guard settingsStorageAvailable, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: "settings.v1")
    }
    private static func legacyCorrected(_ raw: Any?) -> Int64 {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let value = Int64(number.stringValue), value >= 0 else { return 0 }
        return value
    }
    private func persistStatistics() {
        guard statisticsStorageAvailable, let data = try? JSONEncoder().encode(statistics) else { return }
        defaults.set(data, forKey: "statistics.v1")
    }
    /// Call only after verified text replacement; source/action attempts do not count.
    func recordCorrection(category: UsageCategory = .automatic) {
        guard category.isCorrection else { return }
        statistics.record(category, confirmed: true)
        corrected = Int(statistics.correctedTotal)
        defaults.set(corrected, forKey: "corrected") // Keep the previous build's total.
        persistStatistics()
    }
    /// Call only after the requested TIS layout is verified as selected.
    func recordSingleShift() {
        statistics.record(.singleShift, confirmed: true)
        persistStatistics()
    }
    private func recordSoundStarted() {
        statistics.record(.sound, confirmed: true)
        persistStatistics()
    }
    // MARK: Snippets

    private func loadSnippets() {
        guard settingsStorageAvailable, let url = snippetsURL else {
            snippetsStorageAvailable = false; return
        }
        let data: Data?
        if FileManager.default.fileExists(atPath: url.path) {
            guard let read = try? Data(contentsOf: url) else {
                snippetsStorageAvailable = false
                lastStatus = "Файл сниппетов не читается; изменения сниппетов не сохраняются"
                return
            }
            data = read
        } else { data = nil }
        switch SnippetLibrary.load(fileData: data, legacyRules: settings.rules) {
        case .loaded(let library):
            snippets = library; refreshUsableSnippets()
        case .migrated(let library):
            // First launch with snippets: the former rules become snippets with the same ids.
            snippets = library; refreshUsableSnippets(); persistSnippets()
        case .unavailable(let error):
            snippetsStorageAvailable = false
            if case .unsupportedVersion = error {
                lastStatus = "Файл сниппетов создан более новой версией TypeTune; он не изменяется"
            } else { lastStatus = "Файл сниппетов повреждён; он не изменяется" }
        }
    }
    // Validation uses the standard table: Store stays independent of installed input sources
    // (probes compile it alone). Matching while typing uses the installed table.
    private func refreshUsableSnippets() { usableSnippets = snippets.usable() }
    /// Writes the library atomically and keeps the former rules (used with universal mode off)
    /// equal to the literal whole-word snippets.
    @discardableResult
    private func persistSnippets() -> Bool {
        guard snippetsStorageAvailable, let url = snippetsURL else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try snippets.encoded().write(to: url, options: .atomic)
        } catch {
            lastStatus = "Не удалось сохранить сниппеты: \(error.localizedDescription)"
            return false
        }
        let rules = snippets.legacyRules()
        if settings.rules != rules { settings.rules = rules }
        return true
    }
    func snippetIssues(_ snippet: Snippet) -> [SnippetIssue] {
        snippets.issues(for: snippet)
    }
    /// Adds or replaces a snippet. Returns its issues; nothing is saved when there are any.
    @discardableResult
    func saveSnippet(_ snippet: Snippet) -> [SnippetIssue] {
        let issues = snippetIssues(snippet)
        guard issues.isEmpty, snippetsStorageAvailable else { return issues }
        if let index = snippets.snippets.firstIndex(where: { $0.id == snippet.id }) { snippets.snippets[index] = snippet }
        else { snippets.snippets.append(snippet) }
        refreshUsableSnippets(); persistSnippets()
        return []
    }
    func deleteSnippet(_ id: UUID) {
        guard snippetsStorageAvailable else { return }
        snippets.snippets.removeAll { $0.id == id }
        refreshUsableSnippets(); persistSnippets()
    }
    func setSnippet(_ id: UUID, enabled: Bool) {
        guard snippetsStorageAvailable, let index = snippets.snippets.firstIndex(where: { $0.id == id }) else { return }
        snippets.snippets[index].enabled = enabled
        refreshUsableSnippets(); persistSnippets()
    }
    func exportSnippets(to url: URL) {
        do {
            try snippets.encoded().write(to: url, options: .atomic)
            lastStatus = "Сниппеты сохранены в файл: \(snippets.snippets.count)"
        } catch { lastStatus = "Не удалось сохранить файл сниппетов: \(error.localizedDescription)" }
    }
    /// Adds snippets from a TypeTune export. Snippets already present (same id) or with issues
    /// against the current library are skipped and counted.
    func importSnippets(from url: URL) {
        guard snippetsStorageAvailable else { return }
        guard let data = try? Data(contentsOf: url), let imported = try? SnippetLibrary.decode(data) else {
            lastStatus = "Файл не похож на сниппеты TypeTune"; return
        }
        var added = 0, skipped = 0
        for snippet in imported.snippets {
            if snippets.snippets.contains(where: { $0.id == snippet.id }) || !snippetIssues(snippet).isEmpty { skipped += 1; continue }
            snippets.snippets.append(snippet); added += 1
        }
        refreshUsableSnippets(); persistSnippets()
        lastStatus = "Добавлено сниппетов: \(added); пропущено: \(skipped)"
    }

    func learn(_ word: String) {
        let word = word.lowercased()
        if !settings.learnedWords.contains(word) { settings.learnedWords.append(word) }
    }
    func chooseSound() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard NSSound(contentsOf: url, byReference: true) != nil else {
            lastStatus = "Этот звуковой файл не поддерживается"; return
        }
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true).appendingPathComponent("LayoutPilot/Sounds", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
            try FileManager.default.copyItem(at: url, to: target)
            customSoundPath = target.path; settings.sound = true; lastStatus = "Собственный звук выбран"
        } catch { lastStatus = "Не удалось сохранить звук: \(error.localizedDescription)" }
    }
    func playCorrectionSound() {
        activeSound?.stop()
        activeSound = !customSoundPath.isEmpty ? NSSound(contentsOfFile: customSoundPath, byReference: true) : nil
        if activeSound == nil { activeSound = NSSound(named: "Pop") }
        if activeSound?.play() == true { recordSoundStarted() }
    }
    private enum HeaderImageError: Error { case notOwned, invalid, tooLarge, dimensions }
    private static let maximumHeaderBytes = 32 * 1024 * 1024
    private static func headerImagesDirectory(create: Bool) throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: create).appendingPathComponent("LayoutPilot/HeaderImages", isDirectory: true)
    }
    private static func readHeaderBytes(_ url: URL) throws -> Data {
        let resource = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard resource.isRegularFile == true else { throw HeaderImageError.invalid }
        guard let size = resource.fileSize, size > 0, size <= maximumHeaderBytes else { throw HeaderImageError.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // Read a fixed upper bound even if the selected file changes after stat.
        let data = try file.read(upToCount: maximumHeaderBytes + 1) ?? Data()
        guard !data.isEmpty, data.count <= maximumHeaderBytes else { throw HeaderImageError.tooLarge }
        return data
    }
    private static func headerImage(from data: Data) throws -> NSImage {
        guard !data.isEmpty, data.count <= maximumHeaderBytes else { throw HeaderImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { throw HeaderImageError.invalid }
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216 else { throw HeaderImageError.dimensions }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048,
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw HeaderImageError.invalid
        }
        return NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height)))
    }
    func chooseHeaderImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Выберите собственное изображение шапки (до 32 МБ)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importHeaderImage(from: url)
    }
    /// Explicit user-selected URL (open panel or header drop), never a global
    /// clipboard read. Preserve the original and validate copied bytes first.
    func importHeaderImage(from url: URL) {
        guard url.isFileURL else {
            lastStatus = "Для шапки выберите локальный файл изображения"
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Self.readHeaderBytes(url)
            try storeHeaderImage(data, preferredExtension: url.pathExtension)
        } catch { reportHeaderImageFailure(error) }
    }
    /// Bytes explicitly dropped on our header, for example a TIFF item provider.
    /// UI callers dispatch here on main; no background capture is introduced.
    func importHeaderImage(data: Data) {
        do { try storeHeaderImage(data, preferredExtension: "image") }
        catch { reportHeaderImageFailure(error) }
    }
    private func storeHeaderImage(_ data: Data, preferredExtension: String) throws {
        let image = try Self.headerImage(from: data)
        let directory = try Self.headerImagesDirectory(create: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = preferredExtension.lowercased()
        let safeExtension = !ext.isEmpty && ext.count <= 12 && ext.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            ? ext : "image"
        let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(safeExtension)
        // Exact validated bytes: no re-encoding, original mutation, or deletion.
        try data.write(to: target, options: .atomic)
        headerImagePath = target.path
        headerImage = image
        lastStatus = "Собственное изображение шапки сохранено"
    }
    private func reportHeaderImageFailure(_ error: Error) {
        switch error {
        case HeaderImageError.tooLarge:
            lastStatus = "Выберите изображение размером не больше 32 МБ"
        case HeaderImageError.dimensions:
            lastStatus = "Изображение слишком большое: максимум 8192 × 8192 и 16 мегапикселей"
        default:
            lastStatus = "Не удалось открыть или сохранить изображение. Выберите другой файл."
        }
    }
    func resetHeaderImage() {
        // Copies are intentionally retained in our own HeaderImages directory;
        // clearing a setting must never delete an original or another file.
        headerImagePath = ""
        headerImage = nil
        lastStatus = "Изображение шапки сброшено"
    }
    func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
