import Foundation
import Combine

@MainActor
final class PatrolStore: ObservableObject {
    @Published private(set) var checkpoints: [Checkpoint] = []
    @Published private(set) var events: [PatrolEvent] = []
    @Published private(set) var route: PatrolRoute?
    @Published private(set) var activeRound: PatrolRound?
    @Published private(set) var completedRounds: [PatrolRound] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isReady = false
    @Published var message: String?

    private let storage: any PatrolStorage
    var isBusy: Bool { isLoading || isSaving }

    var nextCheckpoint: Checkpoint? {
        guard let route, let round = activeRound,
              round.scannedCheckpointIDs.count < route.checkpointIDs.count else { return nil }
        let id = route.checkpointIDs[round.scannedCheckpointIDs.count]
        return checkpoints.first(where: { $0.id == id })
    }

    init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storage = PatrolFileStorage(fileURL: fileURL ?? directory.appendingPathComponent("patrol-data.json"))
    }

    init(storage: any PatrolStorage) {
        self.storage = storage
    }

    func load() async {
        guard !isBusy, !isReady else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let state = try await storage.load()
            try state.validate()
            publish(state)
            isReady = true
            message = nil
        } catch {
            message = "Could not load patrol data. Existing data was not replaced: \(error.localizedDescription)"
        }
    }

    func startRound() async {
        guard isReady, !isBusy else { return }
        guard activeRound == nil, let route else {
            message = "A round is already active, or no route is configured."
            return
        }
        let state = SavedPatrolState(checkpoints: checkpoints, events: events, route: route,
                                     activeRound: PatrolRound(routeID: route.id), completedRounds: completedRounds)
        await commit(state, success: "Patrol started. Scan checkpoints in order.")
    }

    func recordScan(_ rawCode: String) async {
        guard isReady, !isBusy else { return }
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
            let state = SavedPatrolState(checkpoints: checkpoints, events: updatedEvents, route: route,
                                         activeRound: advanced.isComplete ? nil : advanced,
                                         completedRounds: updatedCompletedRounds)
            await commit(state, success: advanced.isComplete
                         ? "Patrol completed. All checkpoints verified." : "Verified: \(checkpoint.name)")
        } catch {
            message = error.localizedDescription
        }
    }

    func clearMessage() { message = nil }

    private func commit(_ state: SavedPatrolState, success: String) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await storage.save(state)
            publish(state)
            message = success
        } catch {
            message = "Could not save patrol data: \(error.localizedDescription)"
        }
    }

    private func publish(_ state: SavedPatrolState) {
        checkpoints = state.checkpoints
        events = state.events
        route = state.route
        activeRound = state.activeRound
        completedRounds = state.completedRounds
    }
}
