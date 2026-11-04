import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: PatrolStore

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                CheckpointsView()
            }
            .tabItem { Label("Checkpoints", systemImage: "qrcode.viewfinder") }

            NavigationStack {
                HistoryView()
            }
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
            Section {
                Label("Registered checkpoints: \(store.checkpoints.count)", systemImage: "mappin.and.ellipse")
                Label("Scans recorded: \(store.events.count)", systemImage: "checkmark.shield")
            } header: {
                Text("Patrol overview")
            }
            Section {
                Button {
                    scanning = true
                } label: {
                    Label("Scan checkpoint", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                }
            } footer: {
                Text("Starter app: checkpoint data is stored locally on this device.")
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
            if store.events.isEmpty {
                ContentUnavailableView("No scans yet", systemImage: "clock",
                                       description: Text("Verified checkpoint scans appear here."))
            } else {
                ForEach(store.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.checkpointName).font(.headline)
                        Text(event.scannedAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Scan History")
    }
}
