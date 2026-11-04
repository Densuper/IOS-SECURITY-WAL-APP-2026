import Foundation

@MainActor
final class PatrolStore: ObservableObject {
    @Published private(set) var checkpoints: [Checkpoint] = []
    @Published private(set) var events: [PatrolEvent] = []
    @Published var message: String?

    private let fileURL: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("patrol-data.json")
        load()
    }

    func recordScan(_ rawCode: String) {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let checkpoint = checkpoints.first(where: { $0.code == code }) else {
            message = "Unregistered checkpoint. Scan a QR code assigned to this site."
            return
        }
        events.insert(PatrolEvent(checkpoint: checkpoint), at: 0)
        save()
        message = "Verified: \(checkpoint.name)"
    }

    func clearMessage() { message = nil }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PatrolData.self, from: data) else {
            checkpoints = [
                Checkpoint(name: "Lobby", code: "SP-LOBBY-001", location: "Ground floor"),
                Checkpoint(name: "Stairwell", code: "SP-STAIR-002", location: "First floor"),
                Checkpoint(name: "Roof Access", code: "SP-ROOF-003", location: "Roof")
            ]
            save()
            return
        }
        checkpoints = decoded.checkpoints
        events = decoded.events
    }

    private func save() {
        let payload = PatrolData(checkpoints: checkpoints, events: events)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            message = "Could not save patrol data: \(error.localizedDescription)"
        }
    }
}
