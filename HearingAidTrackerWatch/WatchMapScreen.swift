import SwiftUI
import MapKit
import Combine

struct WatchMapScreen: View {
    @EnvironmentObject var ble: WatchBLEManager
    @EnvironmentObject var loc: WatchLocationManager

    // Toronto as a pleasant default if GPS not yet available
    private let fallback = CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832)

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Use Map's content builder for annotations (MapContent), not overlay.
            Map(position: .constant(.region(region))) {
                if let c = loc.coordinate {
                    Annotation("You", coordinate: c) {
                        Image(systemName: "mappin.circle.fill")
                            .imageScale(.large)
                    }
                } else {
                    Annotation("Fallback", coordinate: fallback) {
                        Image(systemName: "mappin.circle")
                            .imageScale(.large)
                    }
                }
            }
            .task { loc.request() } // start location on appear
            // Use the publisher instead of onChange(of:) for best compatibility.
            .onReceive(loc.$coordinate.compactMap { $0 }) { c in
                withAnimation(.easeInOut(duration: 0.25)) {
                    region.center = c
                }
            }
            .edgesIgnoringSafeArea(.all)

            // Top status pill: battery + BLE state
            HStack(spacing: 6) {
                if let b = ble.batteryLevel {
                    Image(systemName: "battery.100")
                        .font(.caption2)
                    Text("\(b)%")
                        .font(.caption2)
                        .monospacedDigit()
                }
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(color(for: ble.connectionState))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(6)
        }
        // Bottom controls bar
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                if ble.connectionState == .scanning {
                    Button("Stop") { ble.stopScanning() }
                } else {
                    Button("Scan") { ble.scanNow() }
                }
                if ble.connectionState == .connected, ble.hasWriteCharacteristic {
                    Button("LED") {
                        ble.ledOn()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ble.ledOff() }
                    }
                }
            }
            .font(.caption2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 6)
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func color(for s: WatchBLEManager.State) -> Color {
        switch s {
        case .idle, .disconnected: return .gray
        case .scanning:            return .yellow
        case .connecting:          return .orange
        case .connected:           return .green
        case .error:               return .red
        }
    }
}

#Preview {
    WatchMapScreen()
        .environmentObject(WatchBLEManager())
        .environmentObject(WatchLocationManager())
}
