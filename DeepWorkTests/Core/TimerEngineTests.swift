import Foundation
import Testing
@testable import DeepWorkCore

final class TimerEngineTests {
    private let start = Date(timeIntervalSince1970: 1_792_300_000.125)

    @Test func F009_startRevalidatesDurationsAndClock() throws {
        var engine = TimerEngine()
        #expect(throws: ModelValidationError.self) {
            try engine.start(configuration: FocusConfiguration(), at: instant(0))
        }
        for minutes in [0, 481] {
            #expect(throws: ModelValidationError.self) {
                try engine.start(configuration: configuration(focus: minutes), at: instant(0))
            }
        }
        #expect(throws: ModelValidationError.self) {
            try engine.start(configuration: configuration(), at: TimerInstant(elapsed: .nan, wallDate: start))
        }
        #expect(engine.state == .setup)
        #expect(engine.liveRecord == nil)
        #expect(engine.activeCheckpoint == nil)
    }

    @Test func F009_startSnapshotsDurationsAndCannotCreateASecondLiveRecord() throws {
        var engine = try running()
        let id = try #require(engine.liveRecord?.id)
        let records = try engine.start(configuration: configuration(focus: 2, rest: 3), at: instant(10))
        #expect(records.isEmpty)
        #expect(engine.liveRecord?.id == id)
        #expect(engine.focusMinutes == 1)
        #expect(engine.breakMinutes == 1)
        #expect(engine.remainingSeconds == 60)
        try #require(engine.activeCheckpoint).validate()
    }

    @Test func F013_countdownRoundsUpAndAllowsThreeDigitMinutes() throws {
        var engine = try running(focus: 480, rest: 1, repeats: false)
        #expect(engine.countdownText == "480:00")
        #expect(engine.menuBarTitle == "480:00 - Deep work")
        engine.reconcile(at: instant(0.001))
        #expect(engine.countdownText == "480:00")
        engine.reconcile(at: instant(28_799.999))
        #expect(engine.countdownText == "00:01")
        engine.reconcile(at: instant(28_800))
        #expect(engine.countdownText == "01:00")
        #expect(engine.menuBarTitle == "01:00 - Break")
        engine.reconcile(at: instant(28_860))
        #expect(engine.countdownText == "00:00")
        #expect(engine.menuBarTitle == "Deep Work")
        engine.reconcile(at: instant(100_000))
        #expect(engine.countdownText == "00:00")
    }

    @Test func F015_progressTracksOnlyCurrentPhaseAndFreezesWhilePaused() throws {
        var engine = try running(repeats: false)
        #expect(engine.progressFraction == 0)
        engine.reconcile(at: instant(30))
        #expect(engine.progressFraction == 0.5)
        engine.pause(at: instant(30))
        engine.reconcile(at: instant(630))
        #expect(engine.progressFraction == 0.5)
        engine.resume(at: instant(630))
        engine.reconcile(at: instant(660))
        #expect(engine.state == .break)
        #expect(engine.progressFraction == 0)
        engine.reconcile(at: instant(690))
        #expect(engine.progressFraction == 0.5)
        engine.reconcile(at: instant(720))
        #expect(engine.progressFraction == 1)
    }

    @Test func F016_F017_AC06_pauseExcludesTenMinutesAndResumeKeepsRecordIdentity() throws {
        var engine = try running(focus: 60, rest: 10)
        let id = try #require(engine.liveRecord?.id)
        engine.pause(at: instant(1200))
        #expect(engine.remainingSeconds == 2400)
        #expect(engine.liveRecord?.focusedSeconds == 1200)
        engine.reconcile(at: instant(1800))
        #expect(engine.remainingSeconds == 2400)
        #expect(engine.liveRecord?.focusedSeconds == 1200)
        engine.resume(at: instant(1800))
        #expect(engine.liveRecord?.id == id)
        let record = try #require(engine.reconcile(at: instant(4200)).first)
        try record.validate()
        #expect(record.id == id)
        #expect(record.outcome == .complete)
        #expect(record.focusedSeconds == 3600)
        #expect(record.startedAt == start)
        #expect(record.endedAt == start.addingTimeInterval(4200))
        #expect(record.segments == [segment(0, 1200), segment(1800, 4200)])
        #expect(engine.state == .break)
    }

    @Test func F016_F017_duplicatePauseResumeActionsDoNotInventZeroLengthSegments() throws {
        var engine = try running()
        engine.pause(at: instant(0))
        engine.pause(at: instant(0))
        engine.resume(at: instant(0))
        engine.resume(at: instant(0))
        engine.pause(at: instant(17.25))
        engine.pause(at: instant(100))
        engine.resume(at: instant(100))
        engine.resume(at: instant(110))
        let record = try #require(engine.reconcile(at: instant(142.75)).first)
        try record.validate()
        #expect(record.segments == [segment(0, 17.25), segment(100, 142.75)])
        #expect(record.focusedSeconds == 60)
    }

    @Test func F016_AC09_pauseAtDeadlinePausesTheReconciledBreak() throws {
        var engine = try running()
        let records = engine.pause(at: instant(60))
        #expect(records.count == 1)
        #expect(records.first?.outcome == .complete)
        #expect(engine.state == .break)
        #expect(engine.isPaused)
        #expect(engine.remainingSeconds == 60)
        #expect(engine.liveRecord == nil)
    }

    @Test func F023_AC03_fullFocusCompletesExactlyOnceAndBreakAddsNoFocus() throws {
        var engine = try running(focus: 60, rest: 10)
        #expect(engine.reconcile(at: instant(3599.99)).isEmpty)
        let record = try #require(engine.reconcile(at: instant(3600)).first)
        try record.validate()
        #expect(record.focusedSeconds == 3600)
        #expect(record.endedAt == start.addingTimeInterval(3600))
        #expect(engine.state == .break)
        #expect(engine.reconcile(at: instant(3600)).isEmpty)
        #expect(engine.reconcile(at: instant(4199)).isEmpty)
        #expect(engine.liveRecord == nil)
        #expect(engine.reconcile(at: instant(4200)).isEmpty)
        #expect(engine.state == .focus)
        #expect(engine.liveRecord?.focusedSeconds == 0)
        #expect(engine.liveRecord?.id != record.id)
        #expect(engine.liveRecord?.startedAt == start.addingTimeInterval(4200))
    }

    @Test func F024_AC10_delayedCallbackWalksEveryBoundaryOnce() throws {
        var engine = try running()
        let records = engine.reconcile(at: instant(450))
        #expect(records.count == 4)
        #expect(Set(records.map(\.id)).count == 4)
        for (index, record) in records.enumerated() {
            try record.validate()
            let offset = Double(index) * 120
            #expect(record.startedAt == start.addingTimeInterval(offset))
            #expect(record.endedAt == start.addingTimeInterval(offset + 60))
            #expect(record.segments == [segment(offset, offset + 60)])
        }
        #expect(engine.state == .break)
        #expect(engine.remainingSeconds == 30)
        #expect(engine.reconcile(at: instant(450)).isEmpty)
        try #require(engine.activeCheckpoint).validate()
    }

    @Test func F024_sleepAndWallClockChangesUseElapsedClockAccounting() throws {
        var engine = try running(focus: 60, rest: 10)
        engine.reconcile(at: instant(1200, wallOffset: 86_400))
        #expect(engine.remainingSeconds == 2400)
        #expect(engine.liveRecord?.focusedSeconds == 1200)
        engine.reconcile(at: instant(1200, wallOffset: -86_400))
        #expect(engine.remainingSeconds == 2400)
        let records = engine.reconcile(at: instant(7800, wallOffset: -7200))
        #expect(records.count == 2)
        #expect(records.map(\.focusedSeconds) == [3600, 3600])
        #expect(records.map(\.endedAt) == [start.addingTimeInterval(3600), start.addingTimeInterval(7800)])
        #expect(engine.state == .break)
        #expect(engine.remainingSeconds == 600)
        for record in records { try record.validate() }
    }

    @Test func F024_outOfOrderClockReadCannotCountTimeTwice() throws {
        var engine = try running()
        engine.reconcile(at: instant(20))
        engine.reconcile(at: instant(10))
        #expect(engine.remainingSeconds == 40)
        #expect(engine.liveRecord?.focusedSeconds == 20)
        engine.reconcile(at: TimerInstant(elapsed: .infinity, wallDate: start))
        #expect(engine.remainingSeconds == 40)
        let records = engine.reconcile(at: instant(60))
        #expect(records.count == 1)
        #expect(records.first?.focusedSeconds == 60)
    }

    @Test(arguments: [20.0, 80.0])
    func F010_AC04_uncheckingDuringFocusOrBreakFinishesCurrentPair(at elapsed: Double) throws {
        var engine = try running()
        var records = engine.setRepeating(false, at: instant(elapsed))
        records += engine.reconcile(at: instant(600))
        #expect(records.count == 1)
        #expect(records.first?.outcome == .complete)
        #expect(engine.state == .complete)
        #expect(engine.activeCheckpoint == nil)
        #expect(engine.remainingSeconds == 0)
    }

    @Test func F010_reconcileUsesOldRepeatValueBeforeDisablingAfterDelay() throws {
        var engine = try running()
        let priorRecords = engine.setRepeating(false, at: instant(145))
        #expect(priorRecords.count == 1)
        #expect(engine.state == .focus)
        #expect(engine.remainingSeconds == 35)
        #expect(engine.liveRecord?.startedAt == start.addingTimeInterval(120))
        let records = engine.reconcile(at: instant(600))
        #expect(records.count == 1)
        #expect(engine.state == .complete)
    }

    @Test func F010_AC05_enablingAfterExpiredFinalPairDoesNotStartRetrospectiveCycles() throws {
        var engine = try running(repeats: false)
        let records = engine.setRepeating(true, at: instant(600))
        #expect(records.count == 1)
        #expect(engine.state == .complete)
        #expect(engine.isActive == false)
        #expect(engine.repeats)
        #expect(engine.reconcile(at: instant(1200)).isEmpty)
    }

    @Test func F010_togglingRepeatWhilePausedNeverResumes() throws {
        var engine = try running()
        engine.pause(at: instant(20))
        engine.setRepeating(false, at: instant(100))
        engine.setRepeating(true, at: instant(200))
        #expect(engine.isPaused)
        #expect(engine.remainingSeconds == 40)
        #expect(engine.liveRecord?.focusedSeconds == 20)
    }

    @Test func F018_startAgainReusesDurationsCurrentRepeatAndCreatesFreshRecord() throws {
        var engine = try running(focus: 2, rest: 3, repeats: false)
        let record = try #require(engine.reconcile(at: instant(300)).first)
        engine.setRepeating(true, at: instant(400))
        #expect(engine.state == .complete)
        #expect(engine.restart(at: instant(450)).isEmpty)
        #expect(engine.state == .focus)
        #expect(engine.focusMinutes == 2)
        #expect(engine.breakMinutes == 3)
        #expect(engine.remainingSeconds == 120)
        #expect(engine.repeats)
        #expect(engine.liveRecord?.id != record.id)
        #expect(engine.liveRecord?.startedAt == start.addingTimeInterval(450))
        #expect(engine.liveRecord?.focusedSeconds == 0)
    }

    @Test func F019_earlyTakeBreakRecordsPartialAndStartsFullBreak() throws {
        var engine = try running()
        let phaseID = try #require(engine.phaseID)
        let record = try #require(engine.advance(expectedPhaseID: phaseID, at: instant(17)).first)
        try record.validate()
        #expect(record.outcome == .partial)
        #expect(record.focusedSeconds == 17)
        #expect(engine.state == .break)
        #expect(engine.remainingSeconds == 60)
        #expect(engine.isPaused == false)
    }

    @Test func F019_AC07_takeBreakFromPausedFocusStartsRunningBreak() throws {
        var engine = try running()
        let phaseID = try #require(engine.phaseID)
        engine.pause(at: instant(17))
        let record = try #require(engine.advance(expectedPhaseID: phaseID, at: instant(617)).first)
        try record.validate()
        #expect(record.focusedSeconds == 17)
        #expect(record.outcome == .partial)
        #expect(record.endedAt == start.addingTimeInterval(617))
        #expect(engine.state == .break)
        #expect(engine.isPaused == false)
        engine.reconcile(at: instant(627))
        #expect(engine.remainingSeconds == 50)
    }

    @Test func F020_AC08_skipPausedBreakStartsFreshRunningFocus() throws {
        var engine = try running()
        let record = try #require(engine.reconcile(at: instant(60)).first)
        engine.pause(at: instant(70))
        let phaseID = try #require(engine.phaseID)
        #expect(engine.advance(expectedPhaseID: phaseID, at: instant(700)).isEmpty)
        #expect(engine.state == .focus)
        #expect(engine.isPaused == false)
        #expect(engine.remainingSeconds == 60)
        #expect(engine.liveRecord?.id != record.id)
        #expect(engine.liveRecord?.focusedSeconds == 0)
        #expect(engine.liveRecord?.startedAt == start.addingTimeInterval(700))
    }

    @Test func F021_AC08_finishPausedBreakEndsPairWithoutAnotherRecord() throws {
        var engine = try running(repeats: false)
        let records = engine.pause(at: instant(70))
        #expect(records.count == 1)
        let phaseID = try #require(engine.phaseID)
        #expect(engine.nextActionTitle == "Finish break")
        #expect(engine.advance(expectedPhaseID: phaseID, at: instant(700)).isEmpty)
        #expect(engine.state == .complete)
        #expect(engine.isActive == false)
        #expect(engine.activeCheckpoint == nil)
        #expect(engine.primaryActionTitle == "Start again")
        #expect(engine.nextActionTitle == nil)
        #expect(engine.menuBarTitle == "Deep Work")
    }

    @Test func F022_AC13_endKeepsPositivePartialAndDropsZeroTime() throws {
        var engine = try running()
        #expect(engine.end(at: instant(0)).isEmpty)
        #expect(engine.state == .setup)
        #expect(engine.activeCheckpoint == nil)
        try engine.start(configuration: configuration(repeats: false), at: instant(100))
        let record = try #require(engine.end(at: instant(117.125)).first)
        try record.validate()
        #expect(record.outcome == .partial)
        #expect(record.focusedSeconds == 17.125)
        #expect(engine.state == .setup)
        #expect(engine.repeats == false)
        #expect(engine.menuBarTitle == "Deep Work")
        #expect(engine.end(at: instant(200)).isEmpty)
    }

    @Test func F022_endAtDeadlineKeepsOneCompleteRecordAndEndsReconciledBreak() throws {
        var engine = try running()
        let records = engine.end(at: instant(60))
        #expect(records.count == 1)
        #expect(records.first?.outcome == .complete)
        #expect(engine.state == .setup)
        #expect(engine.end(at: instant(60)).isEmpty)
        try engine.start(configuration: configuration(repeats: false), at: instant(100))
        #expect(engine.reconcile(at: instant(220)).count == 1)
        #expect(engine.end(at: instant(230)).isEmpty)
    }

    @Test func F019_zeroTimeTakeBreakDoesNotCreateARecord() throws {
        var engine = try running()
        let phaseID = try #require(engine.phaseID)
        #expect(engine.advance(expectedPhaseID: phaseID, at: instant(0)).isEmpty)
        #expect(engine.state == .break)
        #expect(engine.remainingSeconds == 60)
    }

    @Test(arguments: [60.0, 120.0, 145.0])
    func F019_F020_AC09_staleNextCannotSkipBoundaryOrLaterSameNamedPhase(at elapsed: Double) throws {
        var engine = try running()
        let oldPhaseID = try #require(engine.phaseID)
        let records = engine.advance(expectedPhaseID: oldPhaseID, at: instant(elapsed))
        #expect(records.count == 1)
        #expect(records.first?.outcome == .complete)
        #expect(engine.phaseID != oldPhaseID)
        if elapsed == 60 {
            #expect(engine.state == .break)
            #expect(engine.remainingSeconds == 60)
        } else {
            #expect(engine.state == .focus)
            #expect(engine.remainingSeconds == 180 - elapsed)
            #expect(engine.liveRecord?.startedAt == start.addingTimeInterval(120))
        }
    }

    @Test func F020_staleSkipAtBreakDeadlineDoesNotEndNewFocus() throws {
        var engine = try running()
        engine.reconcile(at: instant(60))
        let oldPhaseID = try #require(engine.phaseID)
        #expect(engine.advance(expectedPhaseID: oldPhaseID, at: instant(120)).isEmpty)
        #expect(engine.state == .focus)
        #expect(engine.remainingSeconds == 60)
        #expect(engine.liveRecord?.focusedSeconds == 0)
    }

    @Test func F025_checkpointProjectionDoesNotSplitOrDoubleCountRunningSegment() throws {
        var engine = try running()
        for elapsed in stride(from: 5.0, through: 55, by: 5) {
            engine.reconcile(at: instant(elapsed))
            let checkpoint = try #require(engine.activeCheckpoint)
            try checkpoint.validate()
            #expect(checkpoint.focusRecord?.segments == [segment(0, elapsed)])
            #expect(checkpoint.remainingSeconds == 60 - elapsed)
        }
        let record = try #require(engine.reconcile(at: instant(60)).first)
        #expect(record.segments == [segment(0, 60)])
        #expect(record.focusedSeconds == 60)
    }

    @Test func F025_AC12_focusRecoveryExcludesDowntimePreservesIDAndClearsNoticeOnResume() throws {
        var first = try running()
        first.pause(at: instant(10))
        first.resume(at: instant(20))
        first.reconcile(at: instant(30))
        let checkpoint = try #require(first.activeCheckpoint)
        let id = try #require(checkpoint.focusRecord?.id)
        var recovered = try TimerEngine(checkpoint: checkpoint, repeats: true, at: instant(10_000))
        #expect(recovered.isPaused)
        #expect(recovered.isRecovered)
        #expect(recovered.liveRecord?.id == id)
        #expect(recovered.remainingSeconds == 40)
        recovered.reconcile(at: instant(20_000))
        #expect(recovered.liveRecord?.focusedSeconds == 20)
        #expect(recovered.remainingSeconds == 40)
        recovered.resume(at: instant(20_000))
        #expect(recovered.isRecovered == false)
        #expect(recovered.isPaused == false)
        let record = try #require(recovered.reconcile(at: instant(20_040)).first)
        try record.validate()
        #expect(record.id == id)
        #expect(record.startedAt == start)
        #expect(record.segments == [segment(0, 10), segment(20, 30), segment(20_000, 20_040)])
        #expect(record.focusedSeconds == 60)
        #expect(recovered.reconcile(at: instant(20_040)).isEmpty)
    }

    @Test func F025_recoveryAfterBackwardWallClockChangeKeepsSegmentsOrdered() throws {
        var first = try running()
        first.reconcile(at: instant(17))
        let checkpoint = try #require(first.activeCheckpoint)
        var recovered = try TimerEngine(checkpoint: checkpoint, repeats: false,
                                        at: TimerInstant(elapsed: 0, wallDate: start.addingTimeInterval(-3600)))
        try #require(recovered.activeCheckpoint).validate()
        recovered.resume(at: TimerInstant(elapsed: 10, wallDate: start.addingTimeInterval(-3590)))
        let record = try #require(recovered.reconcile(at: TimerInstant(elapsed: 53,
                                        wallDate: start.addingTimeInterval(-3547))).first)
        try record.validate()
        #expect(record.segments == [segment(0, 17), segment(27, 70)])
        #expect(record.focusedSeconds == 60)
    }

    @Test func F025_breakRecoveryPausesWithoutFocusAndManualActionClearsNotice() throws {
        var first = try running()
        first.reconcile(at: instant(80))
        let checkpoint = try #require(first.activeCheckpoint)
        var recovered = try TimerEngine(checkpoint: checkpoint, repeats: true, at: instant(10_000))
        #expect(recovered.state == .break)
        #expect(recovered.isPaused)
        #expect(recovered.isRecovered)
        #expect(recovered.remainingSeconds == 40)
        #expect(recovered.liveRecord == nil)
        recovered.reconcile(at: instant(20_000))
        #expect(recovered.remainingSeconds == 40)
        let phaseID = try #require(recovered.phaseID)
        #expect(recovered.advance(expectedPhaseID: phaseID, at: instant(20_000)).isEmpty)
        #expect(recovered.state == .focus)
        #expect(recovered.isPaused == false)
        #expect(recovered.isRecovered == false)
        #expect(recovered.liveRecord?.focusedSeconds == 0)
    }

    @Test func F025_endRecoveredFocusPreservesOnlySavedTime() throws {
        var first = try running()
        first.reconcile(at: instant(17))
        var recovered = try TimerEngine(checkpoint: #require(first.activeCheckpoint), repeats: true, at: instant(10_000))
        let record = try #require(recovered.end(at: instant(20_000)).first)
        try record.validate()
        #expect(record.focusedSeconds == 17)
        #expect(record.outcome == .partial)
        #expect(recovered.isRecovered == false)
        #expect(recovered.activeCheckpoint == nil)
    }

    @Test func F025_invalidCheckpointIsRejectedBeforeRecovery() throws {
        var first = try running()
        first.reconcile(at: instant(17))
        var checkpoint = try #require(first.activeCheckpoint)
        checkpoint.remainingSeconds = 50
        #expect(throws: ModelValidationError.self) {
            try TimerEngine(checkpoint: checkpoint, repeats: true, at: instant(10_000))
        }
        checkpoint.remainingSeconds = 0
        #expect(throws: ModelValidationError.self) {
            try TimerEngine(checkpoint: checkpoint, repeats: true, at: instant(10_000))
        }
    }

    @Test func F011_F012_F014_displayCopyFollowsUnderlyingPhaseAndRepeat() throws {
        var engine = TimerEngine(repeats: false)
        #expect(engine.phaseTitle == "Set your rhythm.")
        #expect(engine.repeatExplanation == "One deep work cycle and one break, then stop.")
        try engine.start(configuration: configuration(rest: 2, repeats: false), at: instant(0))
        #expect(engine.phaseTitle == "Deep work")
        #expect(engine.caption == "2-minute break next")
        #expect(engine.repeatExplanation == "Stops after your upcoming break.")
        engine.pause(at: instant(10))
        #expect(engine.phaseTitle == "Deep work paused")
        #expect(engine.caption == "Paused time is excluded from your journal.")
        #expect(engine.primaryActionTitle == "Resume")
        let phaseID = try #require(engine.phaseID)
        engine.advance(expectedPhaseID: phaseID, at: instant(20))
        #expect(engine.phaseTitle == "Take a break")
        #expect(engine.caption == "Your final break.")
        #expect(engine.repeatExplanation == "Stops after this break.")
        engine.setRepeating(true, at: instant(20))
        #expect(engine.caption == "1-minute deep work next")
        #expect(engine.repeatExplanation == "Deep work, then break. Repeat until unchecked.")
        engine.pause(at: instant(30))
        #expect(engine.phaseTitle == "Break paused")
        #expect(engine.caption == "Paused time is excluded from your journal.")
        engine.setRepeating(false, at: instant(30))
        engine.advance(expectedPhaseID: try #require(engine.phaseID), at: instant(30))
        #expect(engine.phaseTitle == "Cycle complete")
        #expect(engine.caption == "Saved to your journal.")
        #expect(engine.repeatExplanation == "Session complete. Repeat is off.")
        engine.setRepeating(true, at: instant(30))
        #expect(engine.repeatExplanation == "Your next session will repeat.")
    }

    @Test func F025_SQLiteCheckpointRelaunchAndFinalizationPreserveOneRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepWorkTimerTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = configuration()
        var first = try running()
        first.reconcile(at: instant(17))
        let checkpoint = try #require(first.activeCheckpoint)
        let id = try #require(checkpoint.focusRecord?.id)
        let document = JournalDocument(configuration: config, activeCheckpoint: checkpoint)
        #expect(JournalStore(directory: directory).save(document) == nil)

        var reloaded = JournalStore(directory: directory).load().value
        var recovered = try TimerEngine(checkpoint: #require(reloaded.activeCheckpoint),
                                        repeats: reloaded.configuration.repeats, at: instant(10_000))
        recovered.resume(at: instant(10_000))
        reloaded.records += recovered.reconcile(at: instant(10_043))
        reloaded.activeCheckpoint = recovered.activeCheckpoint
        try reloaded.validate()
        #expect(JournalStore(directory: directory).save(reloaded) == nil)

        let final = JournalStore(directory: directory).load()
        #expect(final.failure == nil)
        #expect(final.value.records.count == 1)
        #expect(final.value.records.first?.id == id)
        #expect(final.value.records.first?.focusedSeconds == 60)
        #expect(final.value.records.first?.segments == [segment(0, 17), segment(10_000, 10_043)])
        #expect(final.value.activeCheckpoint?.phase == .break)
        #expect(final.value.activeCheckpoint?.focusRecord == nil)
    }

    private func configuration(focus: Int = 1, rest: Int = 1, repeats: Bool = true) -> FocusConfiguration {
        FocusConfiguration(focusSelection: .custom, breakSelection: .custom,
                           customFocusMinutes: focus, customBreakMinutes: rest, repeats: repeats)
    }

    private func running(focus: Int = 1, rest: Int = 1, repeats: Bool = true) throws -> TimerEngine {
        var engine = TimerEngine(repeats: repeats)
        try engine.start(configuration: configuration(focus: focus, rest: rest, repeats: repeats), at: instant(0))
        return engine
    }

    private func instant(_ elapsed: TimeInterval, wallOffset: TimeInterval = 0) -> TimerInstant {
        TimerInstant(elapsed: elapsed, wallDate: start.addingTimeInterval(elapsed + wallOffset))
    }

    private func segment(_ from: TimeInterval, _ until: TimeInterval) -> ActiveSegment {
        ActiveSegment(startedAt: start.addingTimeInterval(from), endedAt: start.addingTimeInterval(until))
    }
}
