import SwiftUI

@main
struct HeartRateMatcherApp: App {
    @StateObject private var store = RideStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
