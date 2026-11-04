import XCTest
@testable import SecurePatrol

final class PatrolStorageTests: XCTestCase {
    func testMissingFileCreatesVersionedDataOffMainThread() async throws {
        try await withFile { url in
            let storage = PatrolFileStorage(fileURL: url, readData: {
                XCTAssertFalse(Thread.isMainThread)
                return try Data(contentsOf: $0)
            }, writeData: { data, destination in
                XCTAssertFalse(Thread.isMainThread)
                try data.write(to: destination, options: .atomic)
            })
            let state = try await storage.load()
            XCTAssertEqual(state.checkpoints.count, 3)
            let decoded = try PatrolStateCodec.decode(Data(contentsOf: url))
            XCTAssertEqual(decoded.state.schemaVersion, 1)
            XCTAssertFalse(decoded.needsMigration)
        }
    }

    func testReadFailurePreservesExistingFile() async throws {
        try await withFile { url in
            let original = try JSONEncoder().encode(SavedPatrolState.demo())
            try original.write(to: url)
            let storage = PatrolFileStorage(fileURL: url, readData: { _ in
                throw CocoaError(.fileReadNoPermission)
            })
            do {
                _ = try await storage.load()
                XCTFail("An unreadable file must not create demo data")
            } catch {
                XCTAssertEqual((error as NSError).code, NSFileReadNoPermissionError)
            }
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testMalformedAndFutureFormatsAreNeverRewritten() async throws {
        try await withFile { url in
            let original = try object(SavedPatrolState.demo())
            var future = original
            future["schemaVersion"] = 2
            var incomplete = original
            incomplete.removeValue(forKey: "completedRounds")
            var damagedUnversioned = incomplete
            damagedUnversioned.removeValue(forKey: "schemaVersion")
            var missingRoute = original
            missingRoute.removeValue(forKey: "route")
            var nullRounds = original
            nullRounds["completedRounds"] = NSNull()
            var unknown = original
            unknown["unrecognizedField"] = true
            var mistypedVersion = original
            mistypedVersion["schemaVersion"] = "1"
            let invalidFiles = try [future, incomplete, damagedUnversioned, missingRoute,
                                    nullRounds, unknown, mistypedVersion].map {
                try JSONSerialization.data(withJSONObject: $0)
            } + [Data("{broken".utf8), Data("[]".utf8)]
            for data in invalidFiles {
                try data.write(to: url)
                do {
                    _ = try await PatrolFileStorage(fileURL: url).load()
                    XCTFail("Invalid files must not fall back to legacy migration")
                } catch {}
                XCTAssertEqual(try Data(contentsOf: url), data)
            }
        }
    }

    func testLegacyMigrationPreservesCheckpointsAndEvents() async throws {
        try await withFile { url in
            let fixture = SavedPatrolState.demo()
            let event = PatrolEvent(checkpoint: fixture.checkpoints[0])
            let legacy = PatrolData(checkpoints: fixture.checkpoints, events: [event])
            try JSONEncoder().encode(legacy).write(to: url)
            let state = try await PatrolFileStorage(fileURL: url).load()
            XCTAssertEqual(state.checkpoints.map(\.id), fixture.checkpoints.map(\.id))
            XCTAssertEqual(state.route.checkpointIDs, fixture.checkpoints.map(\.id))
            XCTAssertEqual(state.events.first?.id, event.id)
            XCTAssertNil(state.activeRound)
            XCTAssertTrue(state.completedRounds.isEmpty)
            XCTAssertFalse(try PatrolStateCodec.decode(Data(contentsOf: url)).needsMigration)
        }
    }

    func testUnversionedMigrationPreservesActiveAndCompletedRounds() async throws {
        try await withFile { url in
            var state = SavedPatrolState.demo()
            var complete = PatrolRound(routeID: state.route.id)
            for id in state.route.checkpointIDs {
                complete = try PatrolRouteValidator.advancing(complete, checkpointID: id, route: state.route)
            }
            state.completedRounds = [complete]
            state.activeRound = try PatrolRouteValidator.advancing(PatrolRound(routeID: state.route.id),
                                                                  checkpointID: state.checkpoints[0].id, route: state.route)
            state.events = [PatrolEvent(checkpoint: state.checkpoints[0])]
            var unversioned = try object(state)
            unversioned.removeValue(forKey: "schemaVersion")
            try JSONSerialization.data(withJSONObject: unversioned).write(to: url)
            let restored = try await PatrolFileStorage(fileURL: url).load()
            XCTAssertEqual(restored.route.id, state.route.id)
            XCTAssertEqual(restored.activeRound?.id, state.activeRound?.id)
            XCTAssertEqual(restored.activeRound?.scannedCheckpointIDs, state.activeRound?.scannedCheckpointIDs)
            XCTAssertEqual(restored.completedRounds.first?.id, complete.id)
            XCTAssertEqual(restored.completedRounds.first?.completedAt, complete.completedAt)
            XCTAssertEqual(restored.events.first?.id, state.events.first?.id)
            XCTAssertFalse(try PatrolStateCodec.decode(Data(contentsOf: url)).needsMigration)
        }
    }

    func testFailedMigrationPreservesOriginalAndCanBeRetried() async throws {
        try await withFile { url in
            let state = SavedPatrolState.demo()
            let original = try JSONEncoder().encode(PatrolData(checkpoints: state.checkpoints, events: []))
            try original.write(to: url)
            let storage = PatrolFileStorage(fileURL: url, writeData: { _, _ in
                throw CocoaError(.fileWriteNoPermission)
            })
            do {
                _ = try await storage.load()
                XCTFail("Failed migration must not report a successful load")
            } catch {}
            XCTAssertEqual(try Data(contentsOf: url), original)
            let restored = try await PatrolFileStorage(fileURL: url).load()
            XCTAssertEqual(restored.checkpoints.map(\.id), state.checkpoints.map(\.id))
        }
    }

    func testInconsistentRestoredStatesAreRejectedWithoutRewriting() async throws {
        try await withFile { url in
            let fixture = SavedPatrolState.demo()
            var wrongRoute = fixture
            wrongRoute.activeRound = PatrolRound(routeID: UUID())
            var wrongPrefix = fixture
            var round = PatrolRound(routeID: fixture.route.id)
            round.scannedCheckpointIDs = [fixture.checkpoints[1].id]
            wrongPrefix.activeRound = round
            var unknownCheckpoint = fixture
            unknownCheckpoint.route.checkpointIDs.append(UUID())
            var duplicateCode = fixture
            duplicateCode.checkpoints[1].code = duplicateCode.checkpoints[0].code
            var duplicateID = fixture
            duplicateID.checkpoints[1].id = duplicateID.checkpoints[0].id
            var incompleteHistory = fixture
            incompleteHistory.completedRounds = [PatrolRound(routeID: fixture.route.id)]
            var completedActive = fixture
            var completed = PatrolRound(routeID: fixture.route.id)
            completed.scannedCheckpointIDs = fixture.route.checkpointIDs
            completed.completedAt = completed.startedAt
            completedActive.activeRound = completed
            for state in [wrongRoute, wrongPrefix, unknownCheckpoint, duplicateCode, duplicateID,
                          incompleteHistory, completedActive] {
                let data = try JSONEncoder().encode(state)
                try data.write(to: url)
                do {
                    _ = try await PatrolFileStorage(fileURL: url).load()
                    XCTFail("Inconsistent saved state must be rejected")
                } catch {}
                XCTAssertEqual(try Data(contentsOf: url), data)
            }
        }
    }

    private func object(_ state: SavedPatrolState) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
    }

    private func withFile(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory.appendingPathComponent("patrol.json"))
    }
}
