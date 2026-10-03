import Foundation
import Darwin
import Testing
@testable import TypeTune
@testable import TypeTuneSupport

struct SettingsTransactionTests {
    private final class Harness {
        var disk = Settings()
        var pending: [(settings: Settings, dictionaryOnly: Bool, reply: (Bool) -> Void)] = []
        var errors: [String] = []
        var busy: [Bool] = []
        var autostart: [Bool] = []
        var runtimeFailures = 0
        var beforeSave: (() throws -> Void)?
        var loadError: Error?
        var engine: Engine?
        var eventTime: UInt64 = 1000
        lazy var changes: SettingsTransactions = {
            let changes = SettingsTransactions(initial: disk, environment: .init(
                load: { if let error = self.loadError { throw error }; return self.disk },
                save: { value, expected in
                    let action = self.beforeSave; self.beforeSave = nil; try action?()
                    guard self.disk.generation == expected else { throw SettingsError.conflict }
                    var saved = value; saved.generation = expected + 1; self.disk = saved; return saved
                },
                configure: { value, dictionaryOnly, reply in self.pending.append((value, dictionaryOnly, reply)) },
                autostart: { self.autostart.append($0) }))
            changes.onError = { self.errors.append($0) }
            changes.onBusy = { self.busy.append($0) }
            changes.onRuntimeFailure = { self.runtimeFailures += 1 }
            return changes
        }()
        func ack(_ ok: Bool = true) {
            let update = pending.removeFirst()
            if ok, let engine {
                let status = engine.call(["op": update.dictionaryOnly ? "dictionary_update" : "configure",
                    "words": [String](), "learned": update.settings.learned,
                    "exclusions": update.settings.exclusions])["status"] as? String
                #expect(status == (update.dictionaryOnly ? "dictionary_updated" : "configured"))
            }
            update.reply(ok)
        }
        func useRealEngine() {
            let engine = Engine(); self.engine = engine
            #expect(engine.call(["op": "configure", "words": [String](),
                "learned": disk.learned, "exclusions": disk.exclusions])["status"] as? String == "configured")
            _ = changes
        }
        func key(_ key: String, action: String, text: String? = nil, automatic: Bool = true) -> [String: Any] {
            eventTime += 10
            return engine!.call(["op": "key_event", "automatic": automatic, "event": [
                "key": key, "action": action, "text": text as Any? ?? NSNull(),
                "time_ms": eventTime, "device": NSNull(), "origin": "physical",
                "modifiers": key == "left_shift" && action == "down" ? 1 : 0]])
        }
        func word(_ text: String, automatic: Bool = true) -> [String: Any] {
            for character in text {
                _ = key("letter", action: "down", text: String(character), automatic: automatic)
                _ = key("letter", action: "up", automatic: automatic)
            }
            return key("space", action: "down", automatic: automatic)
        }
        func doubleShift() -> [String: Any] {
            _ = key("left_shift", action: "down")
            _ = key("left_shift", action: "up")
            _ = key("left_shift", action: "down")
            return key("left_shift", action: "up")
        }
        func verify(_ plan: [String: Any]) throws -> [String: Any] {
            #expect(plan["status"] as? String == "inferred_edit")
            let id = try #require(plan["id"])
            let reply = engine!.call(["op": "edit_result", "id": id, "outcome": "verified", "time_ms": eventTime])
            #expect(reply["status"] as? String == "ok")
            return reply["feedback"] as? [String: Any] ?? [:]
        }
        func sourceIsProtected() -> Bool {
            engine!.call(["op": "infer", "text": "ghbdtn ", "automatic": true])["status"] as? String == "ignored"
        }
    }

    @Test func feedbackValidationFailureReconcilesExternalDictionaryWithoutLosingUndo() throws {
        let harness = Harness()
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        harness.disk.learned = (0..<499).map { "fixture" + String(letters[$0 / 26]) + String(letters[$0 % 26]) }
        harness.useRealEngine()
        let feedback = try harness.verify(harness.word("ghbdtn"))
        #expect(feedback["learned_add"] as? [String] == ["привет"])
        #expect(!harness.sourceIsProtected())
        // An independent writer consumes the last available dictionary slot.
        harness.disk.learned.append("ghbdtn"); harness.disk.generation = 1
        harness.changes.feedback(learned: ["привет"], exclusions: [], generation: 0)
        try #require(harness.pending.count == 1)
        #expect(harness.pending[0].dictionaryOnly)
        #expect(harness.pending[0].settings == harness.disk)
        harness.ack()
        #expect(harness.sourceIsProtected())
        #expect(harness.changes.current == harness.disk)
        #expect(harness.disk.generation == 1 && harness.disk.learned.count == 500)
        #expect(!harness.errors.isEmpty && harness.runtimeFailures == 0)
        #expect(harness.doubleShift()["replacement"] as? String == "ghbdtn ")
    }

    @Test func filteredNoopFeedbackRemovesAlreadyEffectiveLearningWithoutLosingReverse() throws {
        let harness = Harness()
        harness.useRealEngine()
        let base = harness.disk
        harness.changes.apply(base, basedOn: base, clearLearned: true)
        harness.ack()
        _ = harness.word("привет", automatic: false)
        _ = harness.key("space", action: "up", automatic: false)
        let feedback = try harness.verify(harness.doubleShift())
        #expect(feedback["learned_add"] as? [String] == ["ghbdtn"])
        #expect(harness.sourceIsProtected())
        harness.changes.feedback(learned: ["ghbdtn"], exclusions: [], generation: 0)
        try #require(harness.pending.count == 1)
        #expect(harness.pending[0].dictionaryOnly)
        harness.ack()
        #expect(!harness.sourceIsProtected())
        #expect(harness.disk.learned.isEmpty && harness.disk.generation == 1)
        #expect(harness.doubleShift()["replacement"] as? String == "привет ")
        #expect(harness.errors.isEmpty && harness.runtimeFailures == 0)
    }

    @Test(arguments: [true, false])
    func unreadableSettingsRestoreKnownDictionaryAndPauseCorrection(restored: Bool) throws {
        let harness = Harness()
        harness.useRealEngine()
        _ = try harness.verify(harness.word("ghbdtn"))
        let feedback = try harness.verify(harness.doubleShift())
        #expect(feedback["exclusions_add"] as? [String] == ["ghbdtn"])
        #expect(harness.sourceIsProtected())
        harness.loadError = CocoaError(.fileReadNoPermission)
        harness.changes.feedback(learned: ["ghbdtn"], exclusions: ["ghbdtn"], generation: 0)
        try #require(harness.pending.count == 1)
        #expect(harness.pending[0].dictionaryOnly)
        #expect(harness.pending[0].settings == harness.changes.current)
        harness.ack(restored)
        #expect(harness.runtimeFailures == 1)
        #expect(!harness.errors.isEmpty)
        #expect(harness.disk == Settings())
        #expect(harness.busy == [true, false])
        if restored {
            #expect(!harness.sourceIsProtected())
            #expect(harness.doubleShift()["replacement"] as? String == "привет ")
        }
    }

    @Test func staleDraftKeepsFeedbackAndUnrelatedSettings() throws {
        let harness = Harness()
        let base = harness.disk
        var draft = base; draft.manualSwitching = false
        harness.changes.feedback(learned: ["привет"], exclusions: [], generation: 0)
        harness.changes.apply(draft, basedOn: base)
        #expect(harness.pending.count == 1)
        #expect(harness.pending[0].dictionaryOnly)
        harness.ack()
        #expect(harness.pending[0].settings.learned == ["привет"])
        #expect(!harness.pending[0].dictionaryOnly)
        harness.ack()
        #expect(harness.disk.learned == ["привет"])
        #expect(!harness.disk.manualSwitching)
        #expect(harness.disk.generation == 2)
        #expect(harness.busy == [true, false])
        #expect(harness.errors.isEmpty)
    }

    @Test func feedbackWaitsForApplyAndUsesNewGenerationWithoutReset() {
        let harness = Harness()
        let base = harness.disk
        var draft = base; draft.playSwitchingSound = true
        harness.changes.apply(draft, basedOn: base)
        harness.changes.feedback(learned: ["github"], exclusions: ["почта"], generation: 0)
        #expect(harness.pending[0].settings.generation == 1)
        harness.ack()
        #expect(harness.pending.count == 1)
        #expect(harness.pending[0].dictionaryOnly)
        #expect(harness.pending[0].settings.generation == 2)
        #expect(harness.pending[0].settings.playSwitchingSound)
        harness.ack()
        #expect(harness.disk.learned == ["github"])
        #expect(harness.disk.exclusions == ["почта"])
    }

    @Test func clearBlocksOldLearningAndPreservesRetoggleState() {
        let harness = Harness()
        harness.disk.generation = 4; harness.disk.learned = ["github"]
        let base = harness.disk
        harness.changes.apply(base.clearingLearned(), basedOn: base, clearLearned: true)
        harness.changes.feedback(learned: ["привет"], exclusions: [], generation: 4)
        #expect(harness.pending[0].dictionaryOnly)
        harness.ack()
        #expect(harness.disk.learned.isEmpty)
        #expect(harness.disk.generation == 5)
        #expect(harness.pending.count == 1)
        #expect(harness.pending[0].dictionaryOnly)
        harness.ack() // Remove the already-effective, filtered feedback.
        #expect(harness.pending.isEmpty)
        harness.changes.feedback(learned: ["почта"], exclusions: [], generation: 5)
        #expect(harness.pending[0].dictionaryOnly)
        harness.ack()
        #expect(harness.disk.learned == ["почта"])
    }

    @Test func clearEmptyDictionaryStillInvalidatesPendingLearning() {
        let harness = Harness()
        let base = harness.disk
        harness.changes.apply(base, basedOn: base, clearLearned: true)
        harness.changes.feedback(learned: ["github"], exclusions: [], generation: 0)
        harness.ack()
        #expect(harness.disk.generation == 1)
        #expect(harness.disk.learned.isEmpty)
        #expect(harness.pending.count == 1)
        harness.ack()
        #expect(harness.pending.isEmpty)
    }

    @Test func explicitExclusionRemovalWinsAgainstOldFeedback() {
        let harness = Harness()
        harness.disk.exclusions = ["github"]
        let base = harness.disk
        var draft = base; draft.exclusions = []
        harness.changes.apply(draft, basedOn: base)
        harness.changes.feedback(learned: ["привет"], exclusions: ["github"], generation: 0)
        harness.ack()
        #expect(harness.pending[0].settings.exclusions.isEmpty)
        harness.ack()
        #expect(harness.disk.exclusions.isEmpty)
        #expect(harness.disk.learned == ["привет"])
    }

    @Test func externalDictionaryRemovalsWinAgainstQueuedFeedback() {
        let harness = Harness()
        harness.disk.learned = ["github", "привет"]
        harness.disk.exclusions = ["почта"]
        _ = harness.changes
        harness.disk.learned = ["привет"]
        harness.disk.exclusions = []
        harness.disk.generation = 1
        harness.changes.feedback(learned: ["github", "слово"], exclusions: ["почта"], generation: 0)
        #expect(harness.pending[0].dictionaryOnly)
        #expect(harness.pending[0].settings.learned == ["привет", "слово"])
        #expect(harness.pending[0].settings.exclusions.isEmpty)
        harness.ack()
        #expect(harness.disk.learned == ["привет", "слово"])
        #expect(harness.disk.exclusions.isEmpty)
        // Saving unrelated feedback at generation 2 must not move the removal
        // barrier beyond the external writer's actual generation 1.
        harness.changes.feedback(learned: ["github"], exclusions: ["почта"], generation: 1)
        harness.ack()
        #expect(harness.disk.learned.contains("github"))
        #expect(harness.disk.exclusions == ["почта"])
    }

    @Test func externalClearBlocksAllOlderLearningButAllowsNewFeedback() {
        let harness = Harness()
        harness.disk.learned = ["github"]
        harness.disk.exclusions = ["почта"]
        _ = harness.changes
        harness.disk.learned = []
        harness.disk.exclusions = []
        harness.disk.generation = 1
        harness.changes.feedback(learned: ["github", "привет"], exclusions: ["почта"], generation: 0)
        #expect(harness.pending[0].settings == harness.disk)
        harness.ack()
        #expect(harness.disk.generation == 1)
        #expect(harness.disk.learned.isEmpty)
        #expect(harness.disk.exclusions.isEmpty)
        harness.changes.feedback(learned: ["github"], exclusions: ["почта"], generation: 1)
        harness.ack()
        #expect(harness.disk.learned == ["github"])
        #expect(harness.disk.exclusions == ["почта"])
    }

    @Test func rejectedAndFutureFeedbackCannotPersist() {
        let harness = Harness()
        harness.changes.feedback(learned: ["github"], exclusions: [], generation: 0)
        harness.ack(false)
        #expect(harness.pending[0].dictionaryOnly)
        harness.ack() // A rejected update must remove effective feedback too.
        #expect(harness.disk.learned.isEmpty)
        #expect(harness.disk.generation == 0)
        #expect(!harness.errors.isEmpty)
        harness.changes.feedback(learned: ["github"], exclusions: [], generation: 100)
        #expect(harness.pending.count == 1)
        harness.ack()
        #expect(harness.pending.isEmpty)
        #expect(harness.disk.learned.isEmpty)
        #expect(harness.errors.count == 2)
    }

    @Test func independentWriterIsReloadedAndUnrelatedEditRebased() {
        let harness = Harness()
        let base = harness.disk
        var draft = base; draft.manualSwitching = false
        harness.changes.apply(draft, basedOn: base)
        harness.beforeSave = {
            harness.disk.displayLayoutFlag = false
            harness.disk.generation = 1
        }
        harness.ack()
        #expect(harness.pending[0].settings == harness.disk)
        harness.ack() // Restore the independently written settings.
        #expect(!harness.pending[0].settings.displayLayoutFlag)
        #expect(!harness.pending[0].settings.manualSwitching)
        #expect(harness.pending[0].settings.generation == 2)
        harness.ack()
        #expect(!harness.disk.displayLayoutFlag)
        #expect(!harness.disk.manualSwitching)
        #expect(harness.errors.isEmpty)
    }

    @Test func saveFailureRestoresDictionaryAndReportsError() {
        let harness = Harness()
        harness.changes.feedback(learned: ["github"], exclusions: [], generation: 0)
        harness.beforeSave = { throw CocoaError(.fileWriteNoPermission) }
        harness.ack()
        #expect(harness.pending[0].dictionaryOnly)
        #expect(harness.pending[0].settings.learned.isEmpty)
        harness.ack()
        #expect(!harness.errors.isEmpty)
        #expect(harness.disk.generation == 0)
        #expect(harness.disk.learned.isEmpty)
        #expect(harness.busy == [true, false])
    }

    @Test func failedRollbackMarksRuntimeUnsafe() {
        let harness = Harness()
        harness.changes.feedback(learned: ["github"], exclusions: [], generation: 0)
        harness.beforeSave = { throw CocoaError(.fileWriteNoPermission) }
        harness.ack()
        harness.ack(false)
        #expect(harness.runtimeFailures == 1)
        #expect(!harness.errors.isEmpty)
    }

    @Test func mergeDetectsConflictingLayoutChoiceButKeepsIndependentLists() throws {
        let base = Settings()
        var draft = base; draft.activeKeyboards = ["first"]
        var current = base; current.activeKeyboards = ["second"]; current.generation = 1
        #expect(throws: SettingsError.conflict) { try SettingsMerge.edit(base: base, proposed: draft, current: current) }
        draft = base; draft.autoDisabledIn = ["com.apple.Terminal"]
        current = base; current.autoDisabledIn = ["com.apple.TextEdit"]; current.generation = 1
        let merged = try SettingsMerge.edit(base: base, proposed: draft, current: current)
        #expect(merged.autoDisabledIn == ["com.apple.Terminal", "com.apple.TextEdit"])
    }

    @Test func externalNoopDraftStillSynchronizesEngineWithDisk() {
        let harness = Harness()
        let base = harness.disk
        _ = harness.changes
        harness.disk.learned = ["github"]; harness.disk.generation = 1
        harness.changes.apply(base, basedOn: base)
        #expect(harness.pending.count == 1)
        #expect(harness.pending[0].dictionaryOnly)
        harness.ack()
        #expect(harness.changes.current == harness.disk)
        #expect(harness.disk.generation == 1)
    }

    @Test func storeLockRejectsCompetingWriterWithoutOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        let store = SettingsStore(url: url)
        let saved = try store.save(Settings(), expected: 0)
        let descriptor = open(url.appendingPathExtension("lock").path, O_RDWR)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        defer { flock(descriptor, LOCK_UN) }
        var proposed = saved; proposed.manualSwitching = false
        #expect(throws: SettingsError.conflict) { try store.save(proposed, expected: 1) }
        #expect(try store.load() == saved)
    }
}
