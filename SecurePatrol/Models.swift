import Foundation

struct Checkpoint: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var code: String
    var location: String

    init(id: UUID = UUID(), name: String, code: String, location: String) {
        self.id = id
        self.name = name
        self.code = code
        self.location = location
    }
}

struct PatrolEvent: Identifiable, Codable {
    var id: UUID
    var checkpointID: UUID
    var checkpointName: String
    var scannedAt: Date

    init(id: UUID = UUID(), checkpoint: Checkpoint, scannedAt: Date = .now) {
        self.id = id
        self.checkpointID = checkpoint.id
        self.checkpointName = checkpoint.name
        self.scannedAt = scannedAt
    }
}

struct PatrolData: Codable {
    var checkpoints: [Checkpoint]
    var events: [PatrolEvent]
}
