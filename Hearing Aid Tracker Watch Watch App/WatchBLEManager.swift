import Foundation
import CoreBluetooth
import Combine

/// Minimal BLE manager for watchOS mirroring the iOS behavior (HM-10/BT05 style LED service)
final class WatchBLEManager: NSObject, ObservableObject {

    enum State: String { case idle, scanning, connecting, connected, disconnected, error }

    struct DeviceInfo: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    // MARK: - Published state
    @Published var devices: [DeviceInfo] = []
    @Published var connectionState: State = .idle
    @Published var connectedID: UUID?
    @Published var batteryLevel: Int?
    @Published var hasWriteCharacteristic: Bool = false
    @Published var statusHint: String = "Bluetooth initializing…"

    // MARK: - BLE constants (HM-10 / BT05 UART-like)
    private let TARGET_NAME_HINT = "BT05" // adjust if needed
    private let LED_SERVICE_UUID = CBUUID(string: "FFE0")
    private let LED_CHAR_UUID = CBUUID(string: "FFE1")
    private let BATTERY_SERVICE_UUID = CBUUID(string: "180F")
    private let BATTERY_LEVEL_CHAR_UUID = CBUUID(string: "2A19")

    // MARK: - CoreBluetooth
    private lazy var central: CBCentralManager = CBCentralManager(delegate: self, queue: .main)
    private var target: CBPeripheral?
    private var ledWriteChar: CBCharacteristic?
    private var stopScanTimer: Timer?
    private var pendingScanRequest: Bool = false

    // MARK: - API
    func scanNow() {
        guard central.state == .poweredOn else {
            pendingScanRequest = true
            statusHint = "Waiting for Bluetooth…"
            return
        }
        startScan()
    }

    func stopScanning() {
        central.stopScan()
        stopScanTimer?.invalidate(); stopScanTimer = nil
        if connectionState == .scanning { connectionState = .idle }
        statusHint = "Scan stopped"
    }

    func disconnect() {
        guard let p = target else { return }
        central.cancelPeripheralConnection(p)
    }

    func ledOn() { writeLED(byte: 0x31 /* ASCII "1" */) }
    func ledOff() { writeLED(byte: 0x30 /* ASCII "0" */) }

    private func writeLED(byte: UInt8) {
        guard connectionState == .connected, let ch = ledWriteChar, let p = target else { return }
        let data = Data([byte])
        p.writeValue(data, for: ch, type: .withResponse)
    }

    // MARK: - Internals
    private func startScan() {
        devices.removeAll()
        connectionState = .scanning
        statusHint = "Scanning nearby…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        stopScanTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false, block: { [weak self] _ in
            self?.stopScanning()
        })
    }
}

extension WatchBLEManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusHint = "Bluetooth ON"
            if pendingScanRequest { pendingScanRequest = false; startScan() }
        case .poweredOff: statusHint = "Bluetooth OFF"
        case .unauthorized: statusHint = "Bluetooth unauthorized"
        case .unsupported: statusHint = "Bluetooth unsupported"
        case .resetting: statusHint = "Bluetooth resetting…"
        case .unknown: statusHint = "Bluetooth unknown"
        @unknown default: statusHint = "Bluetooth error"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? "Unknown"
        let info = DeviceInfo(id: peripheral.identifier, name: name, rssi: RSSI.intValue)

        // Update list (dedup by id)
        if let idx = devices.firstIndex(where: { $0.id == info.id }) {
            devices[idx] = info
        } else {
            devices.append(info)
        }

        // Auto-pick device if name hint matches to reduce taps on watch
        if name.contains(TARGET_NAME_HINT) && target == nil {
            target = peripheral
            central.connect(peripheral, options: nil)
            connectionState = .connecting
            stopScanning()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        connectedID = peripheral.identifier
        peripheral.delegate = self
        peripheral.discoverServices([LED_SERVICE_UUID, BATTERY_SERVICE_UUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .error
        statusHint = "Failed to connect: \(error?.localizedDescription ?? "unknown error")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectionState = .disconnected
        ledWriteChar = nil
        hasWriteCharacteristic = false
        statusHint = "Disconnected"
        target = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error { statusHint = "Service error: \(error.localizedDescription)"; return }
        peripheral.services?.forEach { svc in
            if svc.uuid == LED_SERVICE_UUID {
                peripheral.discoverCharacteristics([LED_CHAR_UUID], for: svc)
            } else if svc.uuid == BATTERY_SERVICE_UUID {
                peripheral.discoverCharacteristics([BATTERY_LEVEL_CHAR_UUID], for: svc)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error { statusHint = "Char error: \(error.localizedDescription)"; return }
        service.characteristics?.forEach { ch in
            if ch.uuid == LED_CHAR_UUID {
                ledWriteChar = ch
                hasWriteCharacteristic = true
            } else if ch.uuid == BATTERY_LEVEL_CHAR_UUID {
                peripheral.setNotifyValue(true, for: ch)
                peripheral.readValue(for: ch)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error { statusHint = "Update error: \(error.localizedDescription)"; return }
        if characteristic.uuid == BATTERY_LEVEL_CHAR_UUID, let v = characteristic.value {
            batteryLevel = v.first.map { Int($0) }
        }
    }
}
