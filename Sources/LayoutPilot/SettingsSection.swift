import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case main, keys, exceptions, words, snippets, application, diagnostics
    var id: Self { self }
    var title: String {
        switch self {
        case .main: return "Исправления"
        case .keys: return "Клавиши"
        case .exceptions: return "Приложения"
        case .words: return "Слова"
        case .snippets: return "Сниппеты"
        case .application: return "Приложение"
        case .diagnostics: return "Диагностика"
        }
    }
    var subtitle: String {
        switch self {
        case .main: return "Что TypeTune исправляет во время набора."
        case .keys: return "Переключение раскладки и быстрые действия."
        case .exceptions: return "Где работают исправления и сниппеты."
        case .words: return "Слова, которые нужно оставлять как есть."
        case .snippets: return "Короткие сокращения для часто используемого текста."
        case .application: return "Запуск, звук и состояние TypeTune."
        case .diagnostics: return "Подключение, проверка раскладки и статистика."
        }
    }
    var symbol: String {
        switch self {
        case .main: return "wand.and.stars"
        case .keys: return "keyboard"
        case .exceptions: return "macwindow"
        case .words: return "character.book.closed"
        case .snippets: return "text.badge.plus"
        case .application: return "slider.horizontal.3"
        case .diagnostics: return "checkmark.shield"
        }
    }
}
