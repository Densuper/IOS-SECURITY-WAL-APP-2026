import Foundation

/// A patrol route specifies the required order of registered checkpoints.
struct PatrolRoute: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var checkpointIDs: [UUID]
}

struct PatrolRound: Identifiable, Codable {
    var id: UUID = UUID()
    var routeID: UUID
    var startedAt: Date = .now
    var completedAt: Date?
    var scannedCheckpointIDs: [UUID] = []

    var isComplete: Bool { completedAt != nil }
}

/// Stateless route validation for integration with the persistent patrol store.
/// Call validate before recording a scan and persist the updated round atomically.
enum PatrolRouteValidator {
    enum ScanError: LocalizedError {
        case roundCompleted
        case routeEmpty
        case unexpectedCheckpoint(expected: UUID)

        var errorDescription: String? {
            switch self {
            case .roundCompleted: return "This patrol round is already complete."
            case .routeEmpty: return "This route has no checkpoints."
            case .unexpectedCheckpoint: return "Scan the next checkpoint in the assigned route."
            }
        }
    }

    static func validate(checkpointID: UUID, route: PatrolRoute, round: PatrolRound) throws {
        guard !round.isComplete else { throw ScanError.roundCompleted }
        guard !route.checkpointIDs.isEmpty else { throw ScanError.routeEmpty }
        let index = round.scannedCheckpointIDs.count
        guard index < route.checkpointIDs.count else { throw ScanError.roundCompleted }
        let expected = route.checkpointIDs[index]
        guard checkpointID == expected else {
            throw ScanError.unexpectedCheckpoint(expected: expected)
        }
    }

    static func advancing(_ round: PatrolRound, checkpointID: UUID, route: PatrolRoute) throws -> PatrolRound {
        try validate(checkpointID: checkpointID, route: route, round: round)
        var updated = round
        updated.scannedCheckpointIDs.append(checkpointID)
        if updated.scannedCheckpointIDs.count == route.checkpointIDs.count {
            updated.completedAt = .now
        }
        return updated
    }
}
