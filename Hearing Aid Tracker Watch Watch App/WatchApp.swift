import SwiftUI

@main
struct HearingAidTrackerWatchApp: App {
    @StateObject private var ble = WatchBLEManager()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(ble)
        }
    }
}
