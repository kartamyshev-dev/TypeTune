public enum EditorSnapshotFailure: Error, Equatable, Sendable {
    case accessibilityDenied, secureInput, targetUnavailable
    case unsupportedApplication, unsupportedField, staleContext
    case deadlineExceeded, axCannotComplete, invalidAttribute, invalidSelection, oversizedText
    case axError(Int32)

    public var diagnosticCode: String {
        if case .axError = self { return "axError" }
        return String(describing: self)
    }

    public var retryable: Bool {
        switch self {
        case .targetUnavailable, .deadlineExceeded, .axCannotComplete: return true
        default: return false
        }
    }

    public var message: String {
        switch self {
        case .accessibilityDenied: return "Нет Универсального доступа"
        case .secureInput: return "Включён защищённый ввод"
        case .targetUnavailable: return "Поле ввода ещё недоступно"
        case .unsupportedApplication: return "Приложение не поддерживает безопасную замену"
        case .unsupportedField: return "Поле не поддерживает безопасную замену"
        case .staleContext: return "Текст или фокус уже изменились"
        case .deadlineExceeded: return "Поле не ответило за отведённое время"
        case .axCannotComplete: return "Редактор временно не отвечает"
        case .invalidAttribute: return "Редактор вернул неподтверждённый контекст"
        case .invalidSelection: return "Не удалось подтвердить положение курсора"
        case .oversizedText: return "Поле превышает ограничение безопасной обработки"
        case .axError: return "Не удалось прочитать поле через Универсальный доступ"
        }
    }
}

/// One deadline covers sequential AX calls; each individual call remains capped at 150 ms.
public struct EditorSnapshotBudget: Sendable {
    public let deadline: Double
    public init(deadline: Double) { self.deadline = deadline }

    public func stage(now: Double) -> EditorSnapshotBudget {
        EditorSnapshotBudget(deadline: min(deadline, now + 0.15))
    }

    public func perform<Value>(now: () -> Double, isCurrent: () -> Bool,
                               operation: (Float) throws -> Value) throws -> Value {
        let current = isCurrent()
        let value = try operation(timeout(now: now(), isCurrent: current))
        let stillCurrent = isCurrent()
        _ = try timeout(now: now(), isCurrent: stillCurrent)
        return value
    }

    public func retry<Value>(now: () -> Double, isCurrent: () -> Bool,
                             pause: (Double) -> Void,
                             attempt: () -> Result<Value, EditorSnapshotFailure>) -> Result<Value, EditorSnapshotFailure> {
        while true {
            do {
                let result = try perform(now: now, isCurrent: isCurrent) { _ in attempt() }
                guard case .failure(let failure) = result, failure.retryable else { return result }
                let current = isCurrent()
                let remaining = try timeout(now: now(), isCurrent: current)
                pause(min(0.005, Double(remaining)))
            } catch let failure as EditorSnapshotFailure {
                return .failure(failure)
            } catch {
                return .failure(.invalidAttribute)
            }
        }
    }

    public func timeout(now: Double, isCurrent: Bool = true) throws -> Float {
        guard isCurrent else { throw EditorSnapshotFailure.staleContext }
        guard deadline.isFinite, now.isFinite, deadline > now else {
            throw EditorSnapshotFailure.deadlineExceeded
        }
        let remaining = min(0.15, deadline - now)
        let timeout = Float(remaining)
        let bounded = Double(timeout) > remaining ? timeout.nextDown : timeout
        guard bounded > 0 else { throw EditorSnapshotFailure.deadlineExceeded }
        return bounded
    }
}
