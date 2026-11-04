import XCTest
@testable import SecurePatrol

final class PatrolStoreTests: XCTestCase {
    @MainActor
    func testCompletedRoundSurvivesReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let store = PatrolStore(fileURL: url)
        await store.load()
        await store.startRound()
        for checkpoint in store.checkpoints { await store.recordScan(checkpoint.code) }

        let reloaded = PatrolStore(fileURL: url)
        await reloaded.load()
        XCTAssertNil(reloaded.activeRound)
        XCTAssertEqual(reloaded.completedRounds.count, 1)
        XCTAssertEqual(reloaded.events.count, store.checkpoints.count)
        XCTAssertEqual(reloaded.completedRounds.first?.scannedCheckpointIDs, store.route?.checkpointIDs)
    }

    @MainActor
    func testFailedStartDoesNotActivateRoundOrReportSuccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let store = PatrolStore(fileURL: url)
        await store.load()
        try blockWrites(to: url)
        await store.startRound()
        XCTAssertNil(store.activeRound)
        XCTAssertTrue(store.message?.hasPrefix("Could not save patrol data:") == true)
    }

    @MainActor
    func testFailedScanDoesNotAdvanceAndCanBeRetried() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let store = PatrolStore(fileURL: url)
        await store.load()
        await store.startRound()
        let first = try XCTUnwrap(store.checkpoints.first)
        try blockWrites(to: url)
        await store.recordScan(first.code)
        XCTAssertEqual(store.activeRound?.scannedCheckpointIDs, [])
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertTrue(store.message?.hasPrefix("Could not save patrol data:") == true)

        try FileManager.default.removeItem(at: url)
        await store.recordScan(first.code)
        XCTAssertEqual(store.activeRound?.scannedCheckpointIDs, [first.id])
        let reloaded = PatrolStore(fileURL: url)
        await reloaded.load()
        XCTAssertEqual(reloaded.events.count, 1)
    }

    @MainActor
    func testFailedFinalScanKeepsRoundActive() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let store = PatrolStore(fileURL: url)
        await store.load()
        await store.startRound()
        for checkpoint in store.checkpoints.dropLast() { await store.recordScan(checkpoint.code) }
        try blockWrites(to: url)
        await store.recordScan(try XCTUnwrap(store.checkpoints.last).code)
        XCTAssertNotNil(store.activeRound)
        XCTAssertTrue(store.completedRounds.isEmpty)
        XCTAssertEqual(store.events.count, store.checkpoints.count - 1)
        XCTAssertTrue(store.message?.hasPrefix("Could not save patrol data:") == true)
    }

    @MainActor
    func testCommandsCannotOverwriteAnInFlightSave() async throws {
        var fixture = SavedPatrolState.demo()
        fixture.activeRound = PatrolRound(routeID: fixture.route.id)
        let storage = PausedPatrolStorage(state: fixture)
        let store = PatrolStore(storage: storage)
        await store.load()
        let firstScan = Task { await store.recordScan(fixture.checkpoints[0].code) }
        await storage.waitForSave()

        XCTAssertTrue(store.isSaving)
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertEqual(store.activeRound?.scannedCheckpointIDs, [])
        XCTAssertNil(store.message)
        await store.recordScan(fixture.checkpoints[1].code)
        await store.startRound()
        let pendingWrites = await storage.writeCount
        XCTAssertEqual(pendingWrites, 1)

        await storage.finishSave()
        await firstScan.value
        XCTAssertFalse(store.isSaving)
        XCTAssertEqual(store.activeRound?.scannedCheckpointIDs, [fixture.checkpoints[0].id])
        XCTAssertEqual(store.events.count, 1)
        let persisted = await storage.load()
        XCTAssertEqual(persisted.events.first?.id, store.events.first?.id)
    }

    @MainActor
    func testFailedLoadDisablesCommandsAndAllowsRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("patrol.json")
        let invalid = Data("{broken".utf8)
        try invalid.write(to: url)
        let store = PatrolStore(fileURL: url)
        await store.load()
        XCTAssertFalse(store.isReady)
        XCTAssertFalse(store.isBusy)
        let loadError = store.message
        await store.startRound()
        await store.recordScan("SP-LOBBY-001")
        XCTAssertEqual(store.message, loadError)
        XCTAssertEqual(try Data(contentsOf: url), invalid)

        try JSONEncoder().encode(SavedPatrolState.demo()).write(to: url)
        await store.load()
        XCTAssertTrue(store.isReady)
        XCTAssertNil(store.message)
        await store.startRound()
        XCTAssertNotNil(store.activeRound)
    }

    private func blockWrites(to url: URL) throws {
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // A nonempty directory cannot be replaced by an atomic file write.
        try Data([1]).write(to: url.appendingPathComponent("blocker"))
    }
}

private actor PausedPatrolStorage: PatrolStorage {
    private var state: SavedPatrolState
    private var pendingSave: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var writeCount = 0

    init(state: SavedPatrolState) { self.state = state }

    func load() -> SavedPatrolState { state }

    func save(_ state: SavedPatrolState) async throws {
        writeCount += 1
        await withCheckedContinuation { continuation in
            pendingSave = continuation
            observer?.resume()
            observer = nil
        }
        self.state = state
    }

    func waitForSave() async {
        if pendingSave != nil { return }
        await withCheckedContinuation { observer = $0 }
    }

    func finishSave() {
        pendingSave?.resume()
        pendingSave = nil
    }
}
