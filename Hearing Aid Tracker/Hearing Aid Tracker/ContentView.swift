import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var loc: LocationManager

    var body: some View {
        TabView {
            // DEVICES TAB
            DevicesTabView()
                .tabItem {
                    Label("Devices", systemImage: "dot.radiowaves.left.and.right")
                }

            // MAP TAB
            MapTabView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
        }
        .onAppear {
            // Ask for location once (for Map tab pin when connected)
            loc.request()
            // Start a scan immediately to populate the Devices tab
            ble.scanNow()
        }
    }
}
