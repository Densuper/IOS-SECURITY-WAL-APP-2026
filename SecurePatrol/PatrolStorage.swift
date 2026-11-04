import Foundation

struct SavedPatrolState: Codable, Sendable {
    var schemaVersion = 1
    var checkpoints: [Checkpoint]
    var events: [PatrolEvent]
    var route: PatrolRoute
    var activeRound: PatrolRound?
    var completedRounds: [PatrolRound]

    func validate() throws {
        let checkpointIDs = Set(checkpoints.map(\.id))
        let codes = checkpoints.map(\.code)
        guard schemaVersion == 1,
              checkpointIDs.count == checkpoints.count,
              Set(codes).count == codes.count,
              codes.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              !route.checkpointIDs.isEmpty,
              Set(route.checkpointIDs).count == route.checkpointIDs.count,
              route.checkpointIDs.allSatisfy({ checkpointIDs.contains($0) }),
              Set(events.map(\.id)).count == events.count,
              events.allSatisfy({ checkpointIDs.contains($0.checkpointID) }) else {
            throw PatrolStorageError.invalidState
        }
        let rounds = completedRounds + (activeRound.map { [$0] } ?? [])
        guard Set(rounds.map(\.id)).count == rounds.count else { throw PatrolStorageError.invalidState }
        for round in rounds { try PatrolRouteValidator.validateRound(round, route: route) }
        guard activeRound?.isComplete != true, completedRounds.allSatisfy(\.isComplete) else {
            throw PatrolStorageError.invalidState
        }
    }

    static func demo() -> SavedPatrolState {
        let checkpoints = [
            Checkpoint(name: "Lobby", code: "SP-LOBBY-001", location: "Ground floor"),
            Checkpoint(name: "Stairwell", code: "SP-STAIR-002", location: "First floor"),
            Checkpoint(name: "Roof Access", code: "SP-ROOF-003", location: "Roof")
        ]
        return SavedPatrolState(checkpoints: checkpoints, events: [],
                                route: PatrolRoute(name: "Default Patrol", checkpointIDs: checkpoints.map(\.id)),
                                activeRound: nil, completedRounds: [])
    }
}

enum PatrolStorageError: LocalizedError {
    case unsupportedFormat
    case invalidState

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "The saved file has an unsupported or incomplete format."
        case .invalidState: return "The saved patrol contains inconsistent checkpoints or rounds."
        }
    }
}

enum PatrolStateCodec {
    /// Recognize formats before decoding. A damaged round-aware file must never fall back to legacy data.
    static func decode(_ data: Data) throws -> (state: SavedPatrolState, needsMigration: Bool) {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PatrolStorageError.unsupportedFormat
        }
        let keys = Set(object.keys)
        let currentKeys: Set<String> = ["schemaVersion", "checkpoints", "events", "route", "activeRound", "completedRounds"]
        let roundKeys = currentKeys.subtracting(["schemaVersion"])
        let requiredRoundKeys = roundKeys.subtracting(["activeRound"])
        let state: SavedPatrolState
        let needsMigration: Bool
        if keys.contains("schemaVersion") {
            guard keys.isSubset(of: currentKeys),
                  requiredRoundKeys.isSubset(of: keys) else { throw PatrolStorageError.unsupportedFormat }
            state = try JSONDecoder().decode(SavedPatrolState.self, from: data)
            guard state.schemaVersion == 1 else { throw PatrolStorageError.unsupportedFormat }
            needsMigration = false
        } else if keys == Set(["checkpoints", "events"]) {
            let legacy = try JSONDecoder().decode(PatrolData.self, from: data)
            state = SavedPatrolState(checkpoints: legacy.checkpoints, events: legacy.events,
                                     route: PatrolRoute(name: "Default Patrol", checkpointIDs: legacy.checkpoints.map(\.id)),
                                     activeRound: nil, completedRounds: [])
            needsMigration = true
        } else {
            guard keys.isSubset(of: roundKeys), requiredRoundKeys.isSubset(of: keys) else {
                throw PatrolStorageError.unsupportedFormat
            }
            // The previous round-aware release had no version field. Add one only after identifying its shape.
            var versioned = object
            versioned["schemaVersion"] = 1
            state = try JSONDecoder().decode(SavedPatrolState.self,
                                             from: JSONSerialization.data(withJSONObject: versioned))
            needsMigration = true
        }
        try state.validate()
        return (state, needsMigration)
    }
}

protocol PatrolStorage: Sendable {
    func load() async throws -> SavedPatrolState
    func save(_ state: SavedPatrolState) async throws
}

/// File reads, JSON processing, migrations and atomic writes run on this actor, away from the main actor.
actor PatrolFileStorage: PatrolStorage {
    private let fileURL: URL
    private let readData: @Sendable (URL) throws -> Data
    private let writeData: @Sendable (Data, URL) throws -> Void

    init(fileURL: URL,
         readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
         writeData: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        self.fileURL = fileURL
        self.readData = readData
        self.writeData = writeData
    }

    func load() throws -> SavedPatrolState {
        let data: Data
        do {
            data = try readData(fileURL)
        } catch {
            let cocoaError = error as NSError
            guard cocoaError.domain == NSCocoaErrorDomain,
                  cocoaError.code == NSFileReadNoSuchFileError || cocoaError.code == NSFileNoSuchFileError else {
                throw error
            }
            let state = SavedPatrolState.demo()
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try save(state)
            return state
        }
        let decoded = try PatrolStateCodec.decode(data)
        if decoded.needsMigration { try save(decoded.state) }
        return decoded.state
    }

    func save(_ state: SavedPatrolState) throws {
        try state.validate()
        let data = try JSONEncoder().encode(state)
        try writeData(data, fileURL)
    }
}
