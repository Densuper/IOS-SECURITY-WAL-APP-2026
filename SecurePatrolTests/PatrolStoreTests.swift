import XCTest
@testable import SecurePatrol

final class PatrolStoreTests: XCTestCase {
    @MainActor
    func testCompletedRoundSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let store = PatrolStore(fileURL: url)
        store.startRound()
        for checkpoint in store.checkpoints { store.recordScan(checkpoint.code) }

        let reloaded = PatrolStore(fileURL: url)
        XCTAssertNil(reloaded.activeRound)
        XCTAssertEqual(reloaded.completedRounds.count, 1)
        XCTAssertEqual(reloaded.events.count, store.checkpoints.count)
        XCTAssertEqual(reloaded.completedRounds.first?.scannedCheckpointIDs, store.route?.checkpointIDs)
    }

    @MainActor
    func testFailedStartDoesNotActivateRoundOrReportSuccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let store = PatrolStore(fileURL: url)
        try blockWrites(to: url)
        store.startRound()
        XCTAssertNil(store.activeRound)
        XCTAssertTrue(store.message?.hasPrefix("Could not save patrol data:") == true)
    }

    @MainActor
    func testFailedScanDoesNotAdvanceAndCanBeRetried() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let store = PatrolStore(fileURL: url)
        store.startRound()
        let first = try XCTUnwrap(store.checkpoints.first)
        try blockWrites(to: url)
        store.recordScan(first.code)
        XCTAssertEqual(store.activeRound?.scannedCheckpointIDs, [])
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertTrue(store.message?.hasPrefix("Could not save patrol data:") == true)

        try FileManager.default.removeItem(at: url)
        store.recordScan(first.code)
        XCTAssertEqual(store.activeRound?.scannedCheckpointIDs, [first.id])
        XCTAssertEqual(PatrolStore(fileURL: url).events.count, 1)
    }

    @MainActor
    func testFailedFinalScanKeepsRoundActive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let store = PatrolStore(fileURL: url)
        store.startRound()
        for checkpoint in store.checkpoints.dropLast() { store.recordScan(checkpoint.code) }
        try blockWrites(to: url)
        store.recordScan(try XCTUnwrap(store.checkpoints.last).code)
        XCTAssertNotNil(store.activeRound)
        XCTAssertTrue(store.completedRounds.isEmpty)
        XCTAssertEqual(store.events.count, store.checkpoints.count - 1)
        XCTAssertTrue(store.message?.hasPrefix("Could not save patrol data:") == true)
    }

    private func blockWrites(to url: URL) throws {
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // A nonempty directory cannot be replaced by an atomic file write.
        try Data([1]).write(to: url.appendingPathComponent("blocker"))
    }
}
