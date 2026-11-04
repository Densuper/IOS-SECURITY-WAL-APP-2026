import Foundation

private struct SavedPatrolState: Codable {
    var checkpoints: [Checkpoint]
    var events: [PatrolEvent]
    var route: PatrolRoute
    var activeRound: PatrolRound?
    var completedRounds: [PatrolRound]
}

@MainActor
final class PatrolStore: ObservableObject {
    @Published private(set) var checkpoints: [Checkpoint] = []
    @Published private(set) var events: [PatrolEvent] = []
    @Published private(set) var route: PatrolRoute?
    @Published private(set) var activeRound: PatrolRound?
    @Published private(set) var completedRounds: [PatrolRound] = []
    @Published var message: String?

    private let fileURL: URL

    var nextCheckpoint: Checkpoint? {
        guard let route, let round = activeRound,
              round.scannedCheckpointIDs.count < route.checkpointIDs.count else { return nil }
        let id = route.checkpointIDs[round.scannedCheckpointIDs.count]
        return checkpoints.first(where: { $0.id == id })
    }

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("patrol-data.json")
        load()
    }

    func startRound() {
        guard activeRound == nil, let route, !route.checkpointIDs.isEmpty else {
            message = "A round is already active, or no route is configured."
            return
        }
        activeRound = PatrolRound(routeID: route.id)
        save()
        message = "Patrol started. Scan checkpoints in order."
    }

    func recordScan(_ rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let checkpoint = checkpoints.first(where: { $0.code == code }) else {
            message = "Unregistered checkpoint."
            return
        }
        guard let route, let round = activeRound else {
            message = "Start a patrol round before scanning."
            return
        }
        do {
            let advanced = try PatrolRouteValidator.advancing(round, checkpointID: checkpoint.id, route: route)
            events.insert(PatrolEvent(checkpoint: checkpoint), at: 0)
            if advanced.isComplete {
                completedRounds.insert(advanced, at: 0)
                activeRound = nil
                message = "Patrol completed. All checkpoints verified."
            } else {
                activeRound = advanced
                message = "Verified: \(checkpoint.name)"
            }
            save()
        } catch {
            message = error.localizedDescription
        }
    }

    func clearMessage() { message = nil }

    private func load() {
        if let data = try? Data(contentsOf: fileURL) {
            if let state = try? JSONDecoder().decode(SavedPatrolState.self, from: data) {
                checkpoints = state.checkpoints
                events = state.events
                route = state.route
                activeRound = state.activeRound
                completedRounds = state.completedRounds
                return
            }
            // Upgrade data written by the first version of the app.
            if let legacy = try? JSONDecoder().decode(PatrolData.self, from: data) {
                checkpoints = legacy.checkpoints
                events = legacy.events
                route = PatrolRoute(name: "Default Patrol", checkpointIDs: legacy.checkpoints.map(\.id))
                save()
                return
            }
            message = "Saved patrol data could not be read. It was not overwritten."
            return
        }
        checkpoints = [
            Checkpoint(name: "Lobby", code: "SP-LOBBY-001", location: "Ground floor"),
            Checkpoint(name: "Stairwell", code: "SP-STAIR-002", location: "First floor"),
            Checkpoint(name: "Roof Access", code: "SP-ROOF-003", location: "Roof")
        ]
        route = PatrolRoute(name: "Default Patrol", checkpointIDs: checkpoints.map(\.id))
        save()
    }

    private func save() {
        guard let route else { return }
        let state = SavedPatrolState(checkpoints: checkpoints, events: events, route: route,
                                     activeRound: activeRound, completedRounds: completedRounds)
        guard let data = try? JSONEncoder().encode(state) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            message = "Could not save patrol data: \(error.localizedDescription)"
        }
    }
}
