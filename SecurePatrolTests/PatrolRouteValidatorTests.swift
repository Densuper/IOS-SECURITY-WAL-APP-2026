import XCTest
@testable import SecurePatrol

final class PatrolRouteValidatorTests: XCTestCase {
    private func fixture() -> (PatrolRoute, PatrolRound, UUID, UUID) {
        let first = UUID()
        let second = UUID()
        let route = PatrolRoute(name: "Test route", checkpointIDs: [first, second])
        return (route, PatrolRound(routeID: route.id), first, second)
    }

    func testCorrectOrderCompletesRound() throws {
        let (route, round, first, second) = fixture()
        let afterFirst = try PatrolRouteValidator.advancing(round, checkpointID: first, route: route)
        XCTAssertFalse(afterFirst.isComplete)
        XCTAssertEqual(afterFirst.scannedCheckpointIDs, [first])
        let finished = try PatrolRouteValidator.advancing(afterFirst, checkpointID: second, route: route)
        XCTAssertTrue(finished.isComplete)
        XCTAssertNotNil(finished.completedAt)
    }

    func testOutOfOrderScanRejectedWithoutAdvancing() throws {
        let (route, round, _, second) = fixture()
        XCTAssertThrowsError(try PatrolRouteValidator.advancing(round, checkpointID: second, route: route))
        XCTAssertTrue(round.scannedCheckpointIDs.isEmpty)
    }

    func testRepeatedScanRejected() throws {
        let (route, round, first, _) = fixture()
        let afterFirst = try PatrolRouteValidator.advancing(round, checkpointID: first, route: route)
        XCTAssertThrowsError(try PatrolRouteValidator.advancing(afterFirst, checkpointID: first, route: route))
    }

    func testCompletedRoundRejectsFurtherScans() throws {
        let (route, round, first, second) = fixture()
        let one = try PatrolRouteValidator.advancing(round, checkpointID: first, route: route)
        let complete = try PatrolRouteValidator.advancing(one, checkpointID: second, route: route)
        XCTAssertThrowsError(try PatrolRouteValidator.advancing(complete, checkpointID: first, route: route))
    }

    func testEmptyRouteRejected() {
        let route = PatrolRoute(name: "Empty", checkpointIDs: [])
        let round = PatrolRound(routeID: route.id)
        XCTAssertThrowsError(try PatrolRouteValidator.validate(checkpointID: UUID(), route: route, round: round))
    }

    func testRoundFromAnotherRouteIsRejected() {
        let (route, _, first, _) = fixture()
        let round = PatrolRound(routeID: UUID())
        XCTAssertThrowsError(try PatrolRouteValidator.advancing(round, checkpointID: first, route: route))
    }

    func testInvalidPreviousScansAreRejected() {
        let (route, initial, _, second) = fixture()
        var round = initial
        round.scannedCheckpointIDs = [second]
        XCTAssertThrowsError(try PatrolRouteValidator.advancing(round, checkpointID: second, route: route))
    }

    func testFullRoundWithoutCompletionTimestampIsRejected() {
        let (route, initial, first, second) = fixture()
        var round = initial
        round.scannedCheckpointIDs = [first, second]
        XCTAssertThrowsError(try PatrolRouteValidator.validateRound(round, route: route))
    }

    func testCompletionBeforeStartIsRejected() {
        let (route, initial, first, second) = fixture()
        var round = initial
        round.scannedCheckpointIDs = [first, second]
        round.completedAt = round.startedAt.addingTimeInterval(-1)
        XCTAssertThrowsError(try PatrolRouteValidator.validateRound(round, route: route))
    }
}
