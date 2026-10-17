/// A delivery acknowledgement and a verified text edit are different proofs.
public struct InputRecovery: Sendable {
    public enum Completion: Sendable { case notApplied, verified, uncertain }
    public enum Action: Equatable, Sendable { case resume, replay, retain, review }
    public private(set) var uncertainMutation = false
    public private(set) var uncertainDeliveries = 0
    public init() {}
    public var requiresReview: Bool { uncertainMutation || uncertainDeliveries > 0 }
    public func mayDetachTap(activeMutation: Bool, outstanding: Int) -> Bool {
        !activeMutation && outstanding == 0 && uncertainDeliveries == 0
    }
    public mutating func observe(_ completion: Completion) {
        if case .uncertain = completion { uncertainMutation = true }
    }
    public mutating func deliveryTimedOut(_ count: Int) {
        uncertainDeliveries += max(0, count)
    }
    public mutating func confirmTextReviewed() {
        uncertainMutation = false; uncertainDeliveries = 0
    }
    public func action(pending: Int, outstanding: Int, contextMatches: Bool) -> Action {
        if requiresReview { return .review }
        if outstanding > 0 { return .retain }
        if pending == 0 { return .resume }
        return contextMatches ? .replay : .retain
    }
}

/// Attempts are bounded until hardware input proves recovery, or the user retries.
public struct TapRecovery: Sendable {
    public enum Action: Equatable, Sendable { case enable, recreate, wait, failed }
    private var attempts = 0
    public init() {}
    public mutating func reset() { attempts = 0 }
    public mutating func next(safe: Bool) -> Action {
        guard safe else { return .wait }
        guard attempts < 2 else { return .failed }
        attempts += 1
        return attempts == 1 ? .enable : .recreate
    }
}

public enum InputServiceStatus: String, Sendable {
    case ready, settingsUnavailable, conflict, sleeping, secureInput, accessibilityDenied
    case listeningDenied, postingDenied, recoveryPending, uncertainResult, tapFailed
    case waitingForContext, unsupportedApplication, unsupportedLayout, unsupportedField, excludedApplication
    public var title: String {
        switch self {
        case .ready: return "Работает"
        case .recoveryPending: return "Ожидает восстановления"
        case .uncertainResult: return "Проверьте последний текст"
        case .tapFailed: return "Не подключена клавиатура"
        case .waitingForContext: return "Ожидает поле ввода"
        default: return "Приостановлен"
        }
    }
    public var message: String {
        switch self {
        case .ready: return "Обработчик готов. Double Shift — исправить; ⌘⌥Z — отменить"
        case .settingsUnavailable: return "Настройки недоступны; исходные данные сохранены"
        case .conflict: return "Завершите другой переключатель раскладки"
        case .sleeping: return "Обработка приостановлена до пробуждения"
        case .secureInput: return "Защищённый ввод включён. Исправления приостановлены"
        case .accessibilityDenied: return "Разрешите Универсальный доступ"
        case .listeningDenied: return "Разрешите Мониторинг ввода"
        case .postingDenied: return "Отправка клавиш не разрешена; исправления в этом приложении недоступны"
        case .recoveryPending: return "Сохранён ввод. Вернитесь в исходное поле и нажмите ⌘⌥R"
        case .uncertainResult: return "Результат последней операции не подтверждён. Проверьте текст перед продолжением"
        case .tapFailed: return "Не удалось восстановить обработчик клавиатуры. Нажмите «Повторить подключение»"
        case .waitingForContext: return "Поле ввода ещё не подтверждено; новый ввод проходит без изменений"
        case .excludedApplication: return "Исправления отключены для активного приложения"
        case .unsupportedApplication: return "В активном приложении исправления не поддерживаются"
        case .unsupportedLayout: return "Активная раскладка не поддерживается; выберите русскую или английскую"
        case .unsupportedField: return "Активное поле не поддерживает безопасное исправление"
        }
    }
}
