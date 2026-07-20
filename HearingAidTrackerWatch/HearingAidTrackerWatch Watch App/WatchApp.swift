import SwiftUI

@main
struct HearingAidTrackerWatchApp: App {
    @StateObject private var ble = WatchBLEManager()
    @StateObject private var loc = WatchLocationManager()
    
    var body: some Scene {
        WindowGroup {
            // Launch directly into the Map screen
            WatchMapScreen()
                .environmentObject(ble)
                .environmentObject(loc)
        }
    }
}
