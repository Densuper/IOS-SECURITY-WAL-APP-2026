import SwiftUI

@main
struct SecurePatrolApp: App {
    @StateObject private var store = PatrolStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
