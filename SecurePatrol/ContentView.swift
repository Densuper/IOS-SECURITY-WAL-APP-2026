import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PatrolStore

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Patrol", systemImage: "figure.walk") }
            NavigationStack { CheckpointsView() }
                .tabItem { Label("Checkpoints", systemImage: "qrcode.viewfinder") }
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .alert("SecurePatrol", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.clearMessage() } }
        )) {
            Button("OK") { store.clearMessage() }
        } message: {
            Text(store.message ?? "")
        }
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var store: PatrolStore
    @State private var scanning = false

    var body: some View {
        List {
            Section("Patrol status") {
                if let round = store.activeRound, let route = store.route {
                    Label("Round in progress", systemImage: "figure.walk")
                    ProgressView(value: Double(round.scannedCheckpointIDs.count),
                                 total: Double(max(route.checkpointIDs.count, 1)))
                    Text("\(round.scannedCheckpointIDs.count) of \(route.checkpointIDs.count) checkpoints")
                        .foregroundStyle(.secondary)
                    if let next = store.nextCheckpoint {
                        LabeledContent("Next checkpoint", value: next.name)
                    }
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan next checkpoint", systemImage: "qrcode.viewfinder")
                    }
                } else {
                    Label("No active patrol", systemImage: "pause.circle")
                    Button("Start patrol round") { store.startRound() }
                        .font(.headline)
                }
            }
            Section("Overview") {
                LabeledContent("Registered checkpoints", value: "\(store.checkpoints.count)")
                LabeledContent("Completed rounds", value: "\(store.completedRounds.count)")
                LabeledContent("Verified scans", value: "\(store.events.count)")
            }
            Section {
                Text("Demo route and QR codes are placeholders. Configure your site's checkpoints before operational use.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SecurePatrol")
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScannerView { value in
                    scanning = false
                    store.recordScan(value)
                }
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { scanning = false }
                    }
                }
            }
        }
    }
}

private struct CheckpointsView: View {
    @EnvironmentObject private var store: PatrolStore

    var body: some View {
        List(store.checkpoints) { checkpoint in
            VStack(alignment: .leading, spacing: 4) {
                Text(checkpoint.name).font(.headline)
                Text(checkpoint.location).foregroundStyle(.secondary)
                Text(checkpoint.code).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
        .navigationTitle("Checkpoints")
    }
}

private struct HistoryView: View {
    @EnvironmentObject private var store: PatrolStore

    var body: some View {
        List {
            Section("Completed rounds") {
                if store.completedRounds.isEmpty {
                    Text("No completed patrols yet").foregroundStyle(.secondary)
                } else {
                    ForEach(store.completedRounds) { round in
                        VStack(alignment: .leading) {
                            Text("Completed patrol").font(.headline)
                            Text(round.completedAt ?? round.startedAt, format: .dateTime.day().month().year().hour().minute())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Verified checkpoint scans") {
                if store.events.isEmpty {
                    Text("No scans yet").foregroundStyle(.secondary)
                } else {
                    ForEach(store.events) { event in
                        VStack(alignment: .leading) {
                            Text(event.checkpointName).font(.headline)
                            Text(event.scannedAt, format: .dateTime.day().month().year().hour().minute())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}
