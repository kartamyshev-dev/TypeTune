import AppKit
import SwiftUI
import ServiceManagement
import TypeTuneSupport
import Darwin
private typealias ViewState<Value> = SwiftUI.State<Value>
typealias Settings = TypeTuneSupport.Settings

final class Controller: ObservableObject {
    @Published var settings=Settings()
    @Published var status="Инициализация…"
    @Published var error=""
    @Published var running=true
    @Published var suggestions:[[String:Any]]=[]
    @Published var applying=false
    let runtime=Runtime()
    let store=SettingsStore(url:FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TypeTune/settings.json"))
    private var tokens:[NSObjectProtocol]=[]
    init() {
        runtime.publish = { [weak self] message,items in self?.status=message;self?.suggestions=items }
        do {settings=try store.load()} catch {self.error=error.localizedDescription;running=false;runtime.setEnabled(false)}
        runtime.configure(settings) { [weak self] ok in
            guard let self, !ok else {return}
            self.error="Движок отклонил настройки"
            self.running=false
            self.runtime.setEnabled(false)
        }
        runtime.start()
        let center=NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.sessionDidResignActiveNotification] {
            tokens.append(center.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in self?.runtime.setSuspended(true)})
        }
        for name in [NSWorkspace.didWakeNotification,NSWorkspace.sessionDidBecomeActiveNotification] {
            tokens.append(center.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in self?.runtime.setSuspended(false)})
        }
        for (name,suspended) in [("com.apple.screenIsLocked",true),("com.apple.screenIsUnlocked",false)] {
            tokens.append(DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name(name),object:nil,queue:.main){[weak self] _ in self?.runtime.setSuspended(suspended)})
        }
    }
    func toggle() {running.toggle();runtime.setEnabled(running)}
    func permissions() {
        _=CGRequestListenEventAccess();_=CGRequestPostEventAccess()
        let options=[kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _=AXIsProcessTrustedWithOptions(options)
    }
    func apply(_ proposed: Settings) {
        guard !applying else {return};applying=true;error=""
        do {
            try proposed.validate()
            guard try store.load().generation == proposed.generation else {throw SettingsError.conflict}
        } catch {self.error=error.localizedDescription;applying=false;return}
        let previous=settings
        runtime.configure(proposed) { [weak self] ok in
            guard let self else {return}
            guard ok else {self.error="Движок отклонил настройки";self.applying=false;return}
            do {
                if proposed.autostart != previous.autostart {
                    if proposed.autostart {try SMAppService.mainApp.register()} else {try SMAppService.mainApp.unregister()}
                    guard (SMAppService.mainApp.status == .enabled) == proposed.autostart else {throw NSError(domain:"TypeTune",code:1,userInfo:[NSLocalizedDescriptionKey:"Автозапуск требует подтверждения в настройках macOS"])}
                }
                self.settings=try self.store.save(proposed,expected:previous.generation)
                self.applying=false
            } catch {
                self.error=error.localizedDescription
                if let restore=LoginItemIntent.rollbackTarget(desired:proposed.autostart,previous:previous.autostart) {
                    if restore {try? SMAppService.mainApp.register()} else {try? SMAppService.mainApp.unregister()}
                }
                self.runtime.configure(previous) { _ in self.applying=false }
            }
        }
    }
    func addSuggestion(_ item:[String:Any]) {
        guard let word=item["word"] as? String else {return}
        var next=settings
        if item["kind"] as? String == "word" {next.words=Array(Set(next.words+[word])).sorted()}
        else {next.exclusions=Array(Set(next.exclusions+[word])).sorted()}
        apply(next)
    }
}

struct PreferencesView: View {
    @ObservedObject var controller:Controller
    @ViewState private var draft=Settings()
    @ViewState private var words=""
    @ViewState private var exclusions=""
    @ViewState private var applications=""
    private func load() {draft=controller.settings;words=draft.words.joined(separator:"\n");exclusions=draft.exclusions.joined(separator:"\n");applications=draft.applications.joined(separator:"\n")}
    private func lines(_ value:String)->[String] {Array(Set(value.split(whereSeparator:{$0.isNewline}).map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty})).sorted()}
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("TypeTune").font(.largeTitle.bold())
            Text(controller.status).accessibilityIdentifier("runtime-status")
            if !controller.error.isEmpty {Text(controller.error).foregroundStyle(.red).textSelection(.enabled)}
            HStack {
                Button(controller.running ? "Пауза":"Запустить",action:controller.toggle)
                Button("Разрешения macOS",action:controller.permissions)
                Button("Завершить") {NSApp.terminate(nil)}
            }
            TabView {
                VStack(alignment:.leading,spacing:14) {
                    Toggle("Включить режим совместимости",isOn:$draft.compatibility)
                    Text("TypeTune исправляет последнее слово по истории клавиш. Если приложение не раскрывает текст и каретку, результат нельзя подтвердить. В защищённых полях и при Secure Input обработка отключается.").font(.callout).foregroundStyle(.secondary)
                    Toggle("Автокоррекция при нажатии пробела",isOn:$draft.automatic)
                    Toggle("Запускать при входе в macOS",isOn:$draft.autostart)
                    Text("Double Shift: два коротких нажатия одного Shift. Повторный жест возвращает слово и раскладку. Поддерживаются ABC и Русская — ПК.")
                    Text("Автозапуск macOS: \(SMAppService.mainApp.status == .enabled ? "включён":"не включён")").font(.caption)
                    Spacer()
                }.padding().tabItem {Text("Основные")}
                HStack {
                    VStack(alignment:.leading){Text("Слова для автоматики");TextEditor(text:$words).accessibilityIdentifier("user-words")}
                    VStack(alignment:.leading){Text("Исключения слов");TextEditor(text:$exclusions).accessibilityIdentifier("excluded-words")}
                }.padding().tabItem{Text("Словари")}
                VStack(alignment:.leading) {
                    Text("Без автокоррекции — один bundle ID на строку (например, com.apple.Terminal). Double Shift остаётся доступным.")
                    TextEditor(text:$applications)
                }.padding().tabItem{Text("Приложения")}
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        if controller.suggestions.isEmpty {Text("Новых предложений нет. Они появляются после трёх отдельных исправлений или отмен.")}
                        ForEach(Array(controller.suggestions.enumerated()),id:\.offset) {_,item in
                            HStack {
                                Text("\(item["word"] as? String ?? "") — \(item["kind"] as? String == "word" ? "добавить в словарь":"исключить из автокоррекции")")
                                Button("Добавить"){controller.addSuggestion(item)}.disabled(controller.applying)
                                Button("Отклонить"){if let id=item["id"] as? UInt64 {controller.runtime.dismiss(id)}}
                            }
                        }
                    }.padding()
                }.tabItem{Text("Предложения")}
            }
            HStack {
                Text("Настройки: поколение \(controller.settings.generation)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Перечитать",action:load)
                Button(controller.applying ? "Применение…":"Применить") {
                    draft.words=lines(words.lowercased());draft.exclusions=lines(exclusions.lowercased());draft.applications=lines(applications)
                    controller.apply(draft)
                }.disabled(controller.applying).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width:650,height:500).onAppear(perform:load).onChange(of:controller.settings.generation){load()}
    }
}

final class AppDelegate:NSObject,NSApplicationDelegate {
    private var lockFD:Int32 = -1
    private var item:NSStatusItem!
    private var window:NSWindow!
    private var controller:Controller!
    private var statusMenu:StatusMenu?
    func applicationDidFinishLaunching(_ notification:Notification) {
        let directory=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TypeTune")
        do {try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])} catch {NSApp.terminate(nil);return}
        lockFD=open(directory.appendingPathComponent("instance.lock").path,O_CREAT|O_RDWR,0o600)
        guard lockFD>=0,flock(lockFD,LOCK_EX|LOCK_NB)==0 else {NSApp.terminate(nil);return}
        controller=Controller()
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:500),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title="TypeTune — настройки";window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:PreferencesView(controller:controller));window.center()
        item=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        let menu=NSMenu()
        for (title,action) in [("Настройки…",#selector(show)),("Пауза",#selector(toggle)),("Завершить TypeTune",#selector(quit))] {
            let entry=NSMenuItem(title:title,action:action,keyEquivalent:"");entry.target=self;menu.addItem(entry)
            if action == #selector(toggle), let button=item.button {
                statusMenu=StatusMenu(button:button,toggle:entry,
                    running:controller.$running.eraseToAnyPublisher(),
                    status:controller.$status.eraseToAnyPublisher())
            }
        }
        item.menu=menu
        if !controller.settings.compatibility || !controller.error.isEmpty {show()}
    }
    @objc func show(){NSApp.activate(ignoringOtherApps:true);window.makeKeyAndOrderFront(nil)}
    @objc func toggle(){controller.toggle()}
    @objc func quit(){NSApp.terminate(nil)}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {show();return true}
    func applicationWillTerminate(_ notification:Notification){controller?.runtime.stop();if lockFD>=0{close(lockFD)}}
}

@main struct TypeTuneMain {
    static func main() {
        if CommandLine.arguments.contains("--doctor") {
            let engine=Engine()
            let version=engine.call(["op":"protocol"])
            let data:[String:Any] = ["protocol":version,"os":ProcessInfo.processInfo.operatingSystemVersionString,"listen":CGPreflightListenEventAccess(),"post":CGPreflightPostEventAccess(),"accessibility":AXIsProcessTrusted(),"input_source":Native.inputSource().0,"login_item":SMAppService.mainApp.status.rawValue]
            if let json=try? JSONSerialization.data(withJSONObject:data,options:[.prettyPrinted,.sortedKeys]) {print(String(decoding:json,as:UTF8.self))}
            return
        }
        let app=NSApplication.shared;let delegate=AppDelegate();app.delegate=delegate;app.setActivationPolicy(.accessory);app.run()
        withExtendedLifetime(delegate){}
    }
}
