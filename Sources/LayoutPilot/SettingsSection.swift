import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case main, keys, exceptions, snippets, diagnostics
    var id: Self { self }
    var title: String {
        switch self {
        case .main: return "Основное"
        case .keys: return "Клавиши"
        case .exceptions: return "Исключения"
        case .snippets: return "Сниппеты"
        case .diagnostics: return "Проверка"
        }
    }
    var symbol: String {
        switch self {
        case .main: return "slider.horizontal.3"
        case .keys: return "keyboard"
        case .exceptions: return "hand.raised"
        case .snippets: return "text.badge.plus"
        case .diagnostics: return "checkmark.shield"
        }
    }
}
