import SwiftUI

struct DevicesTabView: View {
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Nearby Bluetooth Devices")
                        .font(.headline)
                    Spacer()
                    if ble.connectionState == .scanning {
                        ProgressView().scaleEffect(0.9)
                        Button("Stop") { ble.stopScanning() }
                            .fontWeight(.semibold)
                    } else {
                        Button("Scan") { ble.scanNow() }
                            .fontWeight(.semibold)
                    }
                }

                if let connectedID = ble.connectedID,
                   let connected = ble.devices.first(where: { $0.id == connectedID }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Connected to: \(connected.name.isEmpty ? "(Unnamed)" : connected.name)")
                            .fontWeight(.semibold)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
                }

                if ble.devices.isEmpty {
                    // Text requested earlier, but now we have a dedicated tab:
                    Text("Tap Scan to discover BLE devices, then tap Connect.")
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(ble.devices) { dev in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dev.name.isEmpty ? "(Unnamed)" : dev.name)
                                        .fontWeight(.medium)
                                    Text("RSSI \(dev.rssi)  ·  \(dev.id.uuidString.prefix(8))…")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if ble.connectedID == dev.id && ble.connectionState == .connected {
                                    Image(systemName: "checkmark.seal.fill").imageScale(.large)
                                } else {
                                    Button("Connect") {
                                        ble.connect(to: dev.id)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                if ble.connectionState == .connected {
                    Button(role: .destructive) { ble.disconnect() } label: {
                        Text("Disconnect").frame(maxWidth: .infinity)
                    }
                }
            }
            .padding()
            .navigationTitle("Devices")
        }
    }
}
