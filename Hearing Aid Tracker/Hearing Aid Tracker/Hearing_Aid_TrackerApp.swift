import SwiftUI

@main
struct BLETrackerApp: App {
    @StateObject private var ble = BLEManager()
    @StateObject private var loc = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
                .environmentObject(loc)
        }
    }
}
