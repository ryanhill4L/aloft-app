import AloftStrap
import CoreBluetooth
import Foundation
import Observation

/// The app-side Bluetooth owner. Scans, connects, bonds, feeds frames into the
/// strap package, and writes the ack only after `HistorySync` says the chunk
/// is durable. CoreBluetooth stays here; framing and SQL stay in AloftStrap.
///
/// The Simulator has no CoreBluetooth path to a strap. Prove this on a phone.
@MainActor
@Observable
final class StrapLink: NSObject {
    enum State: Equatable {
        case off, unauthorized, idle, scanning, connecting, bonding, syncing, live, failed(String)
    }

    struct Found: Identifiable, Equatable {
        let id: UUID
        let name: String
        let family: StrapFamily
        let rssi: Int
    }

    private(set) var state: State = .idle
    private(set) var found: [Found] = []
    private(set) var liveBPM: Int?
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var log: [String] = []

    let store: StrapStore?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var family: StrapFamily = .whoop5
    private var reassembler = Reassembler(family: .whoop5)
    private var encoder = CommandEncoder(family: .whoop5)
    private var history: HistorySync?
    private var commandCharacteristic: CBCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]

    private static let maxLogLines = 400
    /// Notifications are handled strictly in arrival order.
    private let incoming: AsyncStream<[UInt8]>.Continuation

    init(store: StrapStore?) {
        self.store = store
        let (stream, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        incoming = continuation
        super.init()
        Task { [weak self] in
            for await bytes in stream { await self?.handle(bytes) }
        }
    }

    /// Creates the central lazily so the Bluetooth prompt appears on the Band
    /// step, not at launch.
    func startScan() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        guard central?.state == .poweredOn else { return }
        found = []
        state = .scanning
        let services = [CBUUID(string: StrapGATT.whoop4.service), CBUUID(string: StrapGATT.whoop5.service)]
        central?.scanForPeripherals(withServices: services)
        note("scan started")
    }

    func connect(_ strap: Found) {
        guard let p = peripherals[strap.id] else { return }
        central?.stopScan()
        family = strap.family
        reassembler = Reassembler(family: family)
        encoder = CommandEncoder(family: family)
        if let store { history = HistorySync(family: family, store: store) }
        peripheral = p
        p.delegate = self
        state = .connecting
        central?.connect(p)
        note("connecting \(strap.name)")
    }

    func disconnect() {
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        state = .idle
    }

    private func note(_ line: String) {
        let stamp = Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
        log.append("\(stamp) \(line)")
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
    }

    private func fail(_ message: String) {
        lastError = message
        state = .failed(message)
        note("error: \(message)")
    }

    private func write(_ bytes: [UInt8]) {
        guard let peripheral, let commandCharacteristic else { return }
        peripheral.writeValue(Data(bytes), for: commandCharacteristic, type: .withResponse)
    }

    private func handle(_ bytes: [UInt8]) async {
        for raw in reassembler.append(bytes) {
            guard let frame = try? Frame(family: family, bytes: raw) else {
                note("dropped frame, bad CRC (\(raw.count) bytes)")
                continue
            }
            guard let history, [.historicalData, .metadata, .event, .consoleLogs].contains(frame.type) else { continue }
            let (outcome, ack) = await history.receive(frame, now: Int64(Date.now.timeIntervalSince1970))
            switch outcome {
            case let .ack(rows, trim):
                if let ack { write(ack) }
                lastSync = .now
                note("chunk stored: \(rows) rows, trim \(trim), acked")
            case .stalled:
                fail("A history write failed. Nothing more is acked until reconnect.")
            case .complete:
                state = .live
                lastSync = .now
                note("history complete")
            case .collected, .ignored:
                break
            }
        }
    }
}

// The central runs on the main queue, so every callback is main-actor work.
extension StrapLink: @MainActor CBCentralManagerDelegate, @MainActor CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: startScan()
        case .unauthorized: state = .unauthorized
        case .poweredOff: state = .off
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let family: StrapFamily = services.contains(CBUUID(string: StrapGATT.whoop4.service)) ? .whoop4 : .whoop5
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Strap"
        let strap = Found(id: peripheral.identifier, name: name, family: family, rssi: RSSI.intValue)
        peripherals[strap.id] = peripheral
        if let i = found.firstIndex(where: { $0.id == strap.id }) { found[i] = strap } else { found.append(strap) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .bonding
        note("connected; discovering")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        fail(error?.localizedDescription ?? "Couldn't connect.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        note("disconnected")
        if case .failed = state { return }
        state = .idle
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let gatt = StrapGATT.forFamily(family)
        let notify = Set((gatt.notify + [StrapGATT.heartRateMeasurement]).map { CBUUID(string: $0) })
        for c in service.characteristics ?? [] {
            if notify.contains(c.uuid) { peripheral.setNotifyValue(true, for: c) }
            if c.uuid == CBUUID(string: gatt.commandWrite) { commandCharacteristic = c }
        }
        guard service.uuid == CBUUID(string: gatt.service), commandCharacteristic != nil else { return }
        // The bond write. WHOOP 4: a battery read. 5/MG: the fixed client hello.
        write(family == .whoop4 ? encoder.frame(.getBatteryLevel) : CommandEncoder.whoop5ClientHello)
        note("bond write sent")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            return fail("Write failed: \(error.localizedDescription). Unpair the strap in the official WHOOP app, close it, then try again.")
        }
        guard state == .bonding, let history else { return }
        state = .syncing
        for frame in encoder.connectSequence(unixSeconds: UInt32(Date.now.timeIntervalSince1970)) { write(frame) }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            write(await history.startFrame())
            note("history offload requested")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        if characteristic.uuid == CBUUID(string: StrapGATT.heartRateMeasurement) {
            if let hr = HeartRateMeasurement(bytes, family: family), hr.contact != .notDetected { liveBPM = hr.bpm }
            return
        }
        incoming.yield(bytes)
    }
}
