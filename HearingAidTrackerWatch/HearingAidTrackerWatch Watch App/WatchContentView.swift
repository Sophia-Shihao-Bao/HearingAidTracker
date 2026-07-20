import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject var ble: WatchBLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status
            HStack {
                Circle()
                    .frame(width: 8, height: 8)
                    .foregroundStyle(color(for: ble.connectionState))
                Text(ble.connectionState.rawValue.capitalized)
                    .font(.footnote)
                Spacer(minLength: 4)
            }

            // Battery (if available)
            if let b = ble.batteryLevel {
                HStack(spacing: 6) {
                    Image(systemName: "battery.100")
                    Text("\(b)%").font(.caption2).monospacedDigit()
                }
            }

            // Device list / connected controls
            if ble.connectionState == .connected {
                connectedControls
            } else {
                deviceList
            }

            Spacer(minLength: 4)

            // Scan/Stop buttons
            if ble.connectionState == .scanning {
                Button("Stop Scan") { ble.stopScanning() }
            } else {
                Button("Scan Nearby") { ble.scanNow() }
            }

            Text(ble.statusHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private var deviceList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ble.devices) { d in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(d.name).font(.caption)
                            Text("RSSI \(d.rssi) dBm").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer()
                    }
                }
                if ble.devices.isEmpty {
                    Text("No devices yet. Tap ‘Scan Nearby’.").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var connectedControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connected").font(.caption).fontWeight(.semibold)
            if ble.hasWriteCharacteristic {
                HStack {
                    Button("LED On") { ble.ledOn() }
                    Button("LED Off") { ble.ledOff() }
                }.font(.caption2)
            } else {
                Text("Write not available").font(.caption2).foregroundStyle(.secondary)
            }
            Button(role: .destructive) { ble.disconnect() } label: {
                Text("Disconnect")
            }
            .font(.caption2)
        }
    }

    private func color(for s: WatchBLEManager.State) -> Color {
        switch s {
        case .idle, .disconnected: return .gray
        case .scanning: return .yellow
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
}

#Preview {
    WatchContentView().environmentObject(WatchBLEManager())
}
