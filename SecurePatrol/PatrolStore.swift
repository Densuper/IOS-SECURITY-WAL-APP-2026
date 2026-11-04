import Foundation
import Combine

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

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            load()
            return
        }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("patrol-data.json")
        load()
    }

    func startRound() {
        guard activeRound == nil, let route, !route.checkpointIDs.isEmpty else {
            message = "A round is already active, or no route is configured."
            return
        }
        let round = PatrolRound(routeID: route.id)
        guard save(activeRound: round, events: events, completedRounds: completedRounds) else { return }
        activeRound = round
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
            var updatedEvents = events
            updatedEvents.insert(PatrolEvent(checkpoint: checkpoint), at: 0)
            var updatedCompletedRounds = completedRounds
            if advanced.isComplete { updatedCompletedRounds.insert(advanced, at: 0) }
            guard save(activeRound: advanced.isComplete ? nil : advanced,
                       events: updatedEvents, completedRounds: updatedCompletedRounds) else { return }
            events = updatedEvents
            if advanced.isComplete {
                completedRounds = updatedCompletedRounds
                activeRound = nil
                message = "Patrol completed. All checkpoints verified."
            } else {
                activeRound = advanced
                message = "Verified: \(checkpoint.name)"
            }
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

    @discardableResult
    private func save() -> Bool {
        save(activeRound: activeRound, events: events, completedRounds: completedRounds)
    }

    private func save(activeRound: PatrolRound?, events: [PatrolEvent],
                      completedRounds: [PatrolRound]) -> Bool {
        guard let route else { return false }
        let state = SavedPatrolState(checkpoints: checkpoints, events: events, route: route,
                                     activeRound: activeRound, completedRounds: completedRounds)
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            message = "Could not save patrol data: \(error.localizedDescription)"
            return false
        }
    }
}
