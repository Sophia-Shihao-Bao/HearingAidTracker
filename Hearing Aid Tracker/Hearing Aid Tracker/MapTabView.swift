import SwiftUI
import MapKit

struct MapTabView: View {
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var loc: LocationManager

    // Pick which coordinate to pin:
    // - If connected: use the PHONE GPS
    // - If not connected: show nothing (or fall back to a fixed spot if you prefer)
    private var pinCoordinate: CLLocationCoordinate2D? {
        switch ble.connectionState {
        case .connected:
            return loc.coordinate    // phone GPS while connected
        default:
            return nil               // or: ble.fixedMapCenter to show Toronto as fallback
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Software")
                    .font(.system(size: 42, weight: .heavy))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // MAP with a pin
                MapView(userCoordinate: pinCoordinate)
                    .frame(height: 320)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black, lineWidth: 1))
                    .cornerRadius(8)
                    .padding(.horizontal, 16)

                // STATUS (Last detected = last connection time; set in BLEManager.didConnect)
                StatusCard(
                    battery: ble.batteryLevel,
                    connection: ble.connectionState.rawValue,
                    lastSeen: ble.lastSeen
                )
                .padding(.horizontal, 16)

                // ACTIONS — Play light turns ON Arduino PIN 13 (your sketch already maps "1" to LED on)
                HStack(spacing: 16) {
                    Button(action: ble.ledOn) {
                        Text("Play light")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black))
                            .cornerRadius(8)
                    }

                    Button(action: openInMaps) {
                        Text("Open navigation\ndirections")
                            .multilineTextAlignment(.center)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)

                if ble.connectionState != .connected {
                    Text("Connect to a device to pin your phone’s current location on the map.")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(Color(red: 0.91, green: 0.94, blue: 0.95))
    }

    private func openInMaps() {
        guard let c = loc.coordinate else { return }
        let placemark = MKPlacemark(coordinate: c)
        let item = MKMapItem(placemark: placemark)
        item.name = "My Current Location"

        let google = URL(string: "comgooglemaps://?q=\(c.latitude),\(c.longitude)&center=\(c.latitude),\(c.longitude)&zoom=15")!
        if UIApplication.shared.canOpenURL(google) {
            UIApplication.shared.open(google)
        } else {
            let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            item.openInMaps(launchOptions: [
                MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: c),
                MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: span)
            ])
        }
    }
}
