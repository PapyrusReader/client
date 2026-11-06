import ActivityKit
import XCTest
@testable import Runner

@MainActor
class RunnerTests: XCTestCase {
    private func snapshot() -> TimerSnapshot {
        TimerSnapshot(id: "native-test", version: "v1", title: "A Wizard of Earthsea", phase: "running",
                      recordedMs: 0, runningSinceMs: Int64(Date().timeIntervalSince1970 * 1000) - 30_000,
                      targetMs: 60_000)
    }

    func testJournalSurvivesReloadAndRejectsStaleControls() throws {
        var journal = TimerJournal(base: snapshot())
        try journal.save()
        try journal.record(sessionId: "native-test", token: "v1", kind: "pause")
        journal = try TimerJournal.load()
        XCTAssertEqual(journal.actions.count, 1)
        XCTAssertEqual(journal.view()?.phase, "paused")
        XCTAssertNil(journal.view()?.runningSinceMs)
        XCTAssertGreaterThanOrEqual(journal.view()!.recordedMs, 30_000)
        try journal.record(sessionId: "native-test", token: "v1", kind: "finish")
        XCTAssertEqual(journal.actions.count, 1)
        try TimerJournal().save()
    }

    func testAcknowledgementPreservesActionsAddedWhileDartWasWriting() throws {
        var journal = TimerJournal(base: snapshot())
        try journal.record(sessionId: "native-test", token: "v1", kind: "pause")
        let pause = journal.actions[0]
        var committed = journal.view()!
        committed.version = pause.id
        committed.token = nil
        try journal.record(sessionId: "native-test", token: pause.id, kind: "resume")
        try journal.acknowledge(through: pause.id, snapshot: committed)
        journal = try TimerJournal.load()
        XCTAssertEqual(journal.actions.count, 1)
        XCTAssertEqual(journal.view()?.phase, "running")
        XCTAssertEqual(journal.base?.version, pause.id)
        try TimerJournal().save()
    }

    func testCountdownClampsAtZeroAfterSuspension() throws {
        let value = snapshot()
        let journal = TimerJournal(base: value)
        let later = value.runningSinceMs! + 3_600_000
        XCTAssertEqual(journal.view(at: later)?.recordedMs, 60_000)
        XCTAssertEqual(journal.view(at: later)?.phase, "finished")
        XCTAssertNil(journal.view(at: later)?.runningSinceMs)
    }

    func testRejectedAcknowledgementDiscardsSuccessorsFromTheOldVersion() throws {
        var journal = TimerJournal(base: snapshot())
        try journal.record(sessionId: "native-test", token: "v1", kind: "pause")
        let pause = journal.actions[0]
        try journal.record(sessionId: "native-test", token: pause.id, kind: "finish")
        var remote = snapshot()
        remote.version = "remote-version"
        remote.phase = "paused"
        remote.runningSinceMs = nil
        remote.recordedMs = 10_000
        try journal.acknowledge(through: pause.id, snapshot: remote)
        journal = try TimerJournal.load()
        XCTAssertTrue(journal.actions.isEmpty)
        XCTAssertEqual(journal.base, remote)
        XCTAssertEqual(journal.view()?.phase, "paused")
        XCTAssertEqual(journal.view()?.recordedMs, 10_000)
        try TimerJournal().save()
    }

    func testLiveActivityIntentPausesResumesAndFinishesWithoutOpeningApp() async throws {
        guard #available(iOS 17.0, *) else { return }
        try TimerJournal(base: snapshot()).save()
        try await TimerLiveActivity.refresh(allowStart: true)
        XCTAssertEqual(Activity<ReadingTimerAttributes>.activities.count, 1)
        _ = try await ReadingTimerIntent(sessionId: "native-test", token: "v1", kind: "pause").perform()
        var view = try XCTUnwrap(TimerJournal.load().view())
        XCTAssertEqual(view.phase, "paused")
        _ = try await ReadingTimerIntent(sessionId: view.id, token: view.controlToken, kind: "resume").perform()
        view = try XCTUnwrap(TimerJournal.load().view())
        XCTAssertEqual(view.phase, "running")
        _ = try await ReadingTimerIntent(sessionId: view.id, token: view.controlToken, kind: "finish").perform()
        XCTAssertNil(try TimerJournal.load().view())
        XCTAssertEqual(try TimerJournal.load().actions.count, 3)
        XCTAssertTrue(Activity<ReadingTimerAttributes>.activities.isEmpty)
        try TimerJournal().save()
    }
}
