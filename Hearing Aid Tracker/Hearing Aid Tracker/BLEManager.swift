import Foundation
import CoreBluetooth
import CoreLocation
import UIKit

final class BLEManager: NSObject, ObservableObject {
    // Keep this enum nested to avoid name clashes
    enum State: String { case idle, scanning, connecting, connected, disconnected, error }

    struct DeviceInfo: Identifiable, Equatable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    // MARK: - Configure for your module
    // If your module shows a different name in LightBlue, update TARGET_NAME_HINT.
    private let TARGET_NAME_HINT = "BT05"                  // e.g. BT05 / HM-10 / AT-09
    // Typical BLE-UART on BT05/HM-10 clones:
    private let LED_SERVICE_UUID = CBUUID(string: "FFE0")
    private let LED_CHAR_UUID    = CBUUID(string: "FFE1")  // writable char (change if your module differs)

    // Optional battery service (only if your device has it)
    private let BATTERY_SERVICE_UUID    = CBUUID(string: "180F")
    private let BATTERY_LEVEL_CHAR_UUID = CBUUID(string: "2A19")

    // Auto-connect when we first see a matching device
    private let AUTO_CONNECT_TO_FIRST_MATCH = true

    // MARK: - Published state for UI
    @Published var connectionState: State = .idle
    @Published var devices: [DeviceInfo] = []
    @Published var connectedID: UUID?
    @Published var batteryLevel: Int?
    /// Last time we were actually connected (shown as "Last detected")
    @Published var lastSeen: Date?

    /// Optional fixed point (kept for compatibility if you still use it somewhere)
    @Published var fixedMapCenter = CLLocationCoordinate2D(latitude: 43.75627757525183,
                                                           longitude: -79.40579436110447)

    /// True when we've discovered a writable characteristic we can use
    @Published var hasWriteCharacteristic: Bool = false

    /// Helpful status strings you can show under the Scan button
    @Published var centralStateDescription: String = "Bluetooth initializing…"
    @Published var authorizationStatusText: String = "Bluetooth permission: Not determined"

    // MARK: - BLE internals
    private var central: CBCentralManager!
    private var target: CBPeripheral?
    private var ledChar: CBCharacteristic?
    private var batteryChar: CBCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]

    private var stopScanTimer: Timer?
    private var pendingScanRequest = false

    override init() {
        super.init()
        // Show Apple's "Turn On Bluetooth" alert if BT is off.
        central = CBCentralManager(delegate: self,
                                   queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: true])
        updateAuthorizationText()
        updateCentralStateText()
    }

    // MARK: - Public API (UI calls these)

    /// Tap-safe scan. If BT isn't ready yet, we queue the scan and auto-run it on .poweredOn.
    func scanNow() {
        guard central.state == .poweredOn else {
            pendingScanRequest = true
            updateCentralStateText()
            return
        }
        startDiscoveryScan()
    }

    func refreshDevicesList() { scanNow() }

    func connect(to id: UUID) {
        guard let p = peripherals[id] else { return }
        connectionState = .connecting
        central.stopScan()
        resetPeripheralState()
        target = p
        p.delegate = self
        print("[BLE] Connecting to \(p.identifier)")
        central.connect(p, options: nil)
    }

    func disconnect() {
        guard let p = target else { return }
        central.cancelPeripheralConnection(p)
    }

    func stopScanning() {
        central.stopScan()
        if connectionState == .scanning { connectionState = .idle }
        stopScanTimer?.invalidate(); stopScanTimer = nil
        pendingScanRequest = false
        updateCentralStateText()
    }

    /// Turn ON the LED (Arduino PIN 13) by sending ASCII "1"
    func ledOn() {
        guard connectionState == .connected else {
            print("[BLE] ledOn(): not connected (state=\(connectionState))"); return
        }
        guard let p = target, let c = ledChar else {
            print("[BLE] ledOn(): missing writable characteristic"); return
        }

        let data = "1".data(using: .utf8)! // ASCII '1' (0x31)

        if c.properties.contains(.writeWithoutResponse) {
            p.writeValue(data, for: c, type: .withoutResponse)
            print("[BLE] wrote 0x31 (\"1\") to \(c.uuid) .withoutResponse")
        } else if c.properties.contains(.write) {
            p.writeValue(data, for: c, type: .withResponse)
            print("[BLE] wrote 0x31 (\"1\") to \(c.uuid) .withResponse")
        } else {
            print("[BLE] ledOn(): characteristic not writable (props=\(c.properties))")
        }
    }

    /// Optional battery read (safe no-op if not present)
    func readBattery() {
        guard let p = target, let bc = batteryChar else { return }
        p.readValue(for: bc)
    }

    /// Convenience for a Settings button if user denies Bluetooth permission
    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // For enabling/disabling Scan button
    var isBluetoothPoweredOn: Bool { central?.state == .poweredOn }

    // MARK: - Private

    private func startDiscoveryScan() {
        devices.removeAll()
        peripherals.removeAll()
        // keep lastSeen (it's "last connected" time)

        connectionState = .scanning
        print("[BLE] Scanning (no service filter)…")
        central.stopScan()
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        stopScanTimer?.invalidate()
        stopScanTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            self?.stopScanning()
            print("[BLE] Discovery scan ended")
        }
        updateCentralStateText()
    }

    private func resetPeripheralState() {
        ledChar = nil
        batteryChar = nil
        batteryLevel = nil
        hasWriteCharacteristic = false
    }

    private func upsertDiscovered(peripheral: CBPeripheral,
                                  advertisementData: [String: Any],
                                  rssi: NSNumber) {
        let rawName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? peripheral.name ?? ""
        let name = rawName.isEmpty ? "(Unnamed)" : rawName
        let info = DeviceInfo(id: peripheral.identifier, name: name, rssi: rssi.intValue)

        peripherals[info.id] = peripheral
        if let idx = devices.firstIndex(where: { $0.id == info.id }) {
            devices[idx] = info
        } else {
            devices.append(info)
        }

        // Sort by name, then strongest RSSI
        devices.sort { a, b in
            let cmp = a.name.localizedCaseInsensitiveCompare(b.name)
            return cmp != .orderedSame ? (cmp == .orderedAscending) : (a.rssi > b.rssi)
        }
    }

    private func looksLikeTarget(_ peripheral: CBPeripheral, adv: [String: Any]) -> Bool {
        let localName = (adv[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        if !TARGET_NAME_HINT.isEmpty && localName.localizedCaseInsensitiveContains(TARGET_NAME_HINT) {
            return true
        }
        let services  = (adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let overflow  = (adv[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID]) ?? []
        return services.contains(LED_SERVICE_UUID) || overflow.contains(LED_SERVICE_UUID)
    }

    private func updateAuthorizationText() {
        if #available(iOS 13.0, *) {
            switch CBManager.authorization {
            case .allowedAlways: authorizationStatusText = "Bluetooth permission: Allowed"
            case .denied:        authorizationStatusText = "Bluetooth permission: Denied"
            case .restricted:    authorizationStatusText = "Bluetooth permission: Restricted"
            case .notDetermined: authorizationStatusText = "Bluetooth permission: Not determined"
            @unknown default:    authorizationStatusText = "Bluetooth permission: Unknown"
            }
        } else {
            authorizationStatusText = "Bluetooth permission: Allowed"
        }
    }

    private func updateCentralStateText() {
        guard let state = central?.state else {
            centralStateDescription = "Bluetooth initializing…"; return
        }
        switch state {
        case .unknown:     centralStateDescription = "Bluetooth initializing…"
        case .resetting:   centralStateDescription = "Bluetooth resetting…"
        case .unsupported: centralStateDescription = "Bluetooth unsupported on this device"
        case .unauthorized:centralStateDescription = "Bluetooth unauthorized (Settings ▸ Privacy & Security ▸ Bluetooth)"
        case .poweredOff:  centralStateDescription = "Bluetooth is OFF"
        case .poweredOn:   centralStateDescription = "Bluetooth is ON"
        @unknown default:  centralStateDescription = "Bluetooth state unknown"
        }
    }
}

// MARK: - CoreBluetooth delegates
extension BLEManager: CBCentralManagerDelegate, CBPeripheralDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateAuthorizationText()
        updateCentralStateText()

        switch central.state {
        case .poweredOn:
            if pendingScanRequest {
                pendingScanRequest = false
                startDiscoveryScan()
            }
        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            break
        @unknown default:
            connectionState = .error
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        upsertDiscovered(peripheral: peripheral, advertisementData: advertisementData, rssi: RSSI)

        if AUTO_CONNECT_TO_FIRST_MATCH &&
            looksLikeTarget(peripheral, adv: advertisementData) &&
            connectionState != .connected &&
            connectionState != .connecting {
            connect(to: peripheral.identifier)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected
        connectedID = peripheral.identifier
        lastSeen = Date()                 // "Last detected" time
        hasWriteCharacteristic = false
        print("[BLE] Connected ✓  Discovering services…")
        peripheral.discoverServices(nil)
        updateCentralStateText()
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        print("[BLE] Failed to connect: \(error?.localizedDescription ?? "unknown")")
        connectionState = .error
        updateCentralStateText()
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        print("[BLE] Disconnected (\(error?.localizedDescription ?? "no error"))")
        connectionState = .disconnected
        if connectedID == peripheral.identifier { connectedID = nil }
        if target?.identifier == peripheral.identifier { target = nil }
        resetPeripheralState()
        updateCentralStateText()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error { print("[BLE] discoverServices error: \(error.localizedDescription)"); return }
        for s in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error = error { print("[BLE] discoverCharacteristics error: \(error.localizedDescription)"); return }

        for c in service.characteristics ?? [] {
            let writable = c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse)

            if c.uuid == LED_CHAR_UUID || writable {
                // Prefer explicit FFE1; otherwise cache the first writable we see
                if ledChar == nil || c.uuid == LED_CHAR_UUID {
                    ledChar = c
                    hasWriteCharacteristic = writable
                    print("[BLE] Cached write characteristic: \(c.uuid) props=\(c.properties)")
                }
            }

            if c.uuid == BATTERY_LEVEL_CHAR_UUID {
                batteryChar = c
                peripheral.readValue(for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error { print("[BLE] didUpdateValue error: \(error.localizedDescription)"); return }
        if characteristic.uuid == BATTERY_LEVEL_CHAR_UUID, let v = characteristic.value {
            batteryLevel = v.first.map { Int($0) }
            print("[BLE] Battery: \(batteryLevel ?? -1)%")
        }
    }
}
