import SwiftUI

struct DevicePickerView: View { // rename to your existing type if needed
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Select Device")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                if ble.connectionState == BLEManager.State.scanning {
                    ProgressView().scaleEffect(0.9)
                    Button("Stop") { ble.stopScanning() }.fontWeight(.semibold)
                } else {
                    Button("Scan") { ble.scanNow() }.fontWeight(.semibold)
                }
            }

            // CHANGED: always show this message instead of “No devices yet. Tap Scan.”
            if ble.devices.isEmpty {
                Text("Connected to device.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(ble.devices) { dev in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(dev.name.isEmpty ? "(Unnamed)" : dev.name)
                                .fontWeight(.medium)
                            Text("RSSI \(dev.rssi)  ·  \(dev.id.uuidString.prefix(8))…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if ble.connectedID == dev.id && ble.connectionState == BLEManager.State.connected {
                            Image(systemName: "checkmark.seal.fill").imageScale(.large)
                        } else {
                            Button("Connect") { ble.connect(to: dev.id) }
                        }
                    }
                    .padding(.vertical, 6)
                }

                if ble.connectionState == BLEManager.State.connected {
                    Button(role: .destructive) { ble.disconnect() } label: {
                        Text("Disconnect").frame(maxWidth: .infinity)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black))
        .cornerRadius(8)
        .padding(.horizontal, 16)
    }
}
