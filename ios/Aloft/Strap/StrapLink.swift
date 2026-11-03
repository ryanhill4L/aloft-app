import AloftStrap
import CoreBluetooth
import Foundation
import Observation

/// The app-side Bluetooth owner. Scans, connects, bonds, feeds frames into the
/// strap package, and writes the ack only after `HistorySync` says the chunk
/// is durable. CoreBluetooth stays here; framing and SQL stay in AloftStrap.
///
/// The Simulator has no CoreBluetooth path to a strap. Prove this on a phone.
/// Every step lands in `trace`, which the Log tab shares.
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

    private(set) var state: State = .idle {
        didSet { if state != oldValue { note("state \(oldValue) → \(state)") } }
    }
    private(set) var found: [Found] = []
    private(set) var liveBPM: Int?
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private(set) var log: [String] = []
    /// Type-36 replies since this connection, newest last. The Log tab prints
    /// the result code from each one.
    private(set) var commandResults: [CommandResponse] = []
    /// The latest GET_ALARM_TIME reply, decoded by the Log tab.
    private(set) var alarmReadback: CommandResponse?
    /// Wrist, alarm, and haptic events from the `event` table, newest last.
    private(set) var strapEvents: [StrapEvent] = []
    /// Last strap-vs-phone clock line. Arming writes one even when the strap clock is unread.
    private(set) var clockNote: String?
    /// Strap unix seconds from a GET_CLOCK body, when that body is a wall clock.
    private var strapClockUnix: UInt32?

    let store: StrapStore?
    let trace: StrapTrace

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var family: StrapFamily = .whoop5
    private var reassembler = Reassembler(family: .whoop5)
    private var whoop4Encoder = CommandEncoder<Whoop4Generation>()
    private var whoop5Encoder = CommandEncoder<Whoop5Generation>()
    private var history: HistorySync?
    private var commandCharacteristic: CBCharacteristic?
    private var peripherals: [UUID: CBPeripheral] = [:]

    private static let maxLogLines = 400
    /// Notifications are handled strictly in arrival order.
    private let incoming: AsyncStream<[UInt8]>.Continuation

    init(store: StrapStore?, trace: StrapTrace) {
        self.store = store
        self.trace = trace
        let (stream, continuation) = AsyncStream.makeStream(of: [UInt8].self)
        incoming = continuation
        super.init()
        if store == nil { note("store unavailable; history will not be acked") }
        Task { [weak self] in
            await self?.reloadEvents()
            for await bytes in stream { await self?.handle(bytes) }
        }
    }

    /// Creates the central lazily so the Bluetooth prompt appears on the Band
    /// step, not at launch.
    func startScan() {
        if central == nil {
            note("creating central")
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        guard central?.state == .poweredOn else {
            note("scan skipped: central \(central.map { Self.describe($0.state) } ?? "nil")")
            return
        }
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
        switch family {
        case .whoop4: whoop4Encoder = CommandEncoder()
        case .whoop5: whoop5Encoder = CommandEncoder()
        }
        if let store { history = HistorySync(family: family, store: store) }
        peripheral = p
        p.delegate = self
        state = .connecting
        central?.connect(p)
        note("connecting \(strap.name) \(strap.id) family \(family) rssi \(strap.rssi)")
    }

    func disconnect() {
        note("disconnect requested")
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        state = .idle
    }

    /// 5/MG command 19. WHOOP 4 uses command 79. Each builder exists only on
    /// that generation's encoder.
    func buzz() {
        switch family {
        case .whoop5:
            note("buzz")
            write(whoop5Encoder.buzz())
        case .whoop4:
            note("haptics")
            write(whoop4Encoder.runHaptics())
        }
    }

    /// Slot 1, two minutes from the phone clock. Logs the strap clock first
    /// when a GET_CLOCK reply has already been read.
    func armInTwoMinutes() {
        let phone = UInt32(Date.now.timeIntervalSince1970)
        if let strap = strapClockUnix {
            let line = "clock before arm: strap \(strap) phone \(phone) delta \(Int64(phone) - Int64(strap))s"
            clockNote = line
            note(line)
        } else {
            let line = "clock before arm: phone \(phone); strap clock not read"
            clockNote = line
            note(line)
        }
        let when = phone &+ 120
        switch family {
        case .whoop5:
            guard let slot = Whoop5Generation.AlarmSlot(rawValue: 1) else { return }
            note("arm slot \(slot.rawValue) at \(when)")
            write(whoop5Encoder.setAlarm(slot: slot, unixSeconds: when))
        case .whoop4:
            note("arm at \(when)")
            write(whoop4Encoder.setAlarm(unixSeconds: when))
        }
    }

    /// GET_ALARM_TIME. 5/MG reads slot 1. The reply lands in `alarmReadback`.
    func readAlarm() {
        switch family {
        case .whoop5:
            guard let slot = Whoop5Generation.AlarmSlot(rawValue: 1) else { return }
            note("read alarm slot \(slot.rawValue)")
            write(whoop5Encoder.getAlarm(slot: slot))
        case .whoop4:
            note("read alarm")
            write(whoop4Encoder.getAlarm())
        }
    }

    /// 5/MG `02 FF` clears every slot. WHOOP 4 has one alarm, body `01`.
    func disarmAll() {
        switch family {
        case .whoop5:
            note("disarm all slots")
            write(whoop5Encoder.disableAllAlarms())
        case .whoop4:
            note("disarm")
            write(whoop4Encoder.disableAlarm())
        }
    }

    func reloadEvents() async {
        guard let store else { return }
        strapEvents = Self.visibleEvents((try? await store.events()) ?? [])
    }

    func commandTitle(_ command: UInt8) -> String {
        if family == .whoop5, command == StrapCommand.Whoop5.buzz.rawValue { return "buzz" }
        if family == .whoop4, command == StrapCommand.Whoop4.runHapticsPattern.rawValue { return "haptics" }
        switch StrapCommand(rawValue: command) {
        case .setAlarmTime: return "set alarm"
        case .getAlarmTime: return "get alarm"
        case .runAlarm: return "run alarm"
        case .disableAlarm: return "disarm"
        case .stopHaptics: return "stop haptics"
        case .getClock: return "get clock"
        case .setClock: return "set clock"
        default: return "cmd \(command)"
        }
    }

    private func note(_ line: String, bytes: [UInt8]? = nil) {
        trace.write(line, bytes: bytes)
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
        guard let peripheral, let commandCharacteristic else {
            note("tx dropped: no command characteristic", bytes: bytes)
            return
        }
        note("tx \(Self.short(commandCharacteristic.uuid))", bytes: bytes)
        peripheral.writeValue(Data(bytes), for: commandCharacteristic, type: .withResponse)
    }

    private func sharedFrame(_ command: StrapCommand, body: [UInt8] = [0x00]) -> [UInt8] {
        switch family {
        case .whoop4: return whoop4Encoder.frame(command, body: body)
        case .whoop5: return whoop5Encoder.frame(command, body: body)
        }
    }

    private func connectFrames(unixSeconds: UInt32) -> [[UInt8]] {
        switch family {
        case .whoop4: return whoop4Encoder.connectSequence(unixSeconds: unixSeconds)
        case .whoop5: return whoop5Encoder.connectSequence(unixSeconds: unixSeconds)
        }
    }

    private func handle(_ bytes: [UInt8]) async {
        for raw in reassembler.append(bytes) {
            guard let frame = try? Frame(family: family, bytes: raw) else {
                note("frame dropped: bad CRC", bytes: raw)
                continue
            }
            if let type = frame.type {
                note("frame \(type) \(raw.count)B")
            } else {
                note("frame type \(frame.rawType) \(raw.count)B")
            }
            if frame.type == .commandResponse {
                if let response = frame.commandResponse {
                    note("response cmd \(response.command) origin \(response.originSequence) result \(response.result) \(response.resultName)")
                    remember(response)
                } else {
                    note("response undecoded")
                }
                continue
            }
            if frame.type == .event {
                if let event = frame.strapEvent {
                    note("event \(event.label) ts \(event.unixSeconds)")
                    if let store {
                        do {
                            try await store.insert([event])
                            strapEvents = Self.visibleEvents(try await store.events())
                        } catch {
                            note("event not stored: \(String(describing: error))")
                        }
                    } else if Self.shows(event) {
                        strapEvents.append(event)
                    }
                } else {
                    note("event undecoded")
                }
                continue
            }
            guard let history, [.historicalData, .metadata, .consoleLogs].contains(frame.type) else { continue }
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

    /// Wrist on/off, alarm set/fired, haptics fired. Other ids stay in the table.
    private static let shownEventIDs: Set<UInt8> = [9, 10, 56, 57, 58, 60, 100]

    private static func shows(_ event: StrapEvent) -> Bool { shownEventIDs.contains(event.id) }

    private static func visibleEvents(_ events: [StrapEvent]) -> [StrapEvent] {
        Array(events.filter(shows).suffix(40))
    }

    private func remember(_ response: CommandResponse) {
        commandResults.append(response)
        if commandResults.count > 20 { commandResults.removeFirst(commandResults.count - 20) }
        if response.command == StrapCommand.getAlarmTime.rawValue { alarmReadback = response }
        if response.command == StrapCommand.getClock.rawValue { noteClock(response) }
    }

    /// GET_CLOCK (11). WHOOP 4 puts unix seconds at the start of the body
    /// (NOOP PostHooks, ryanbr/noop@2a1de760). A 5/MG body that is not a wall
    /// clock is logged and not stored.
    private func noteClock(_ response: CommandResponse) {
        let phone = UInt32(Date.now.timeIntervalSince1970)
        guard response.body.count >= 4 else {
            let line = "strap clock unread: GET_CLOCK result \(response.result) \(response.resultName)"
            clockNote = line
            note(line)
            return
        }
        let b = response.body
        let unix = UInt32(b[0]) | (UInt32(b[1]) << 8) | (UInt32(b[2]) << 16) | (UInt32(b[3]) << 24)
        let delta = Int64(phone) - Int64(unix)
        guard (1_500_000_000...2_200_000_000).contains(unix) else {
            let line = "strap clock \(unix) phone \(phone) delta \(delta)s; not a wall clock"
            clockNote = line
            note(line)
            return
        }
        strapClockUnix = unix
        let line = "strap clock \(unix) phone \(phone) delta \(delta)s"
        clockNote = line
        note(line)
    }

    private static func short(_ uuid: CBUUID) -> String { String(uuid.uuidString.prefix(8)) }

    private static func describe(_ error: Error?) -> String {
        guard let error else { return "ok" }
        let ns = error as NSError
        return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
    }

    private static func describe(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn: "poweredOn"
        case .poweredOff: "poweredOff"
        case .unauthorized: "unauthorized"
        case .unsupported: "unsupported"
        case .resetting: "resetting"
        case .unknown: "unknown"
        @unknown default: "state \(state.rawValue)"
        }
    }

    private static func describe(_ properties: CBCharacteristicProperties) -> String {
        let names: [(CBCharacteristicProperties, String)] = [
            (.read, "read"), (.write, "write"), (.writeWithoutResponse, "writeNoResp"),
            (.notify, "notify"), (.indicate, "indicate"),
        ]
        return names.filter { properties.contains($0.0) }.map(\.1).joined(separator: ",")
    }
}

// The central runs on the main queue, so every callback is main-actor work.
extension StrapLink: @MainActor CBCentralManagerDelegate, @MainActor CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        note("central \(Self.describe(central.state))")
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
        if let i = found.firstIndex(where: { $0.id == strap.id }) {
            found[i] = strap
        } else {
            found.append(strap)
            note("found \(name) \(strap.id) family \(family) rssi \(strap.rssi) services \(services.map(Self.short))")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .bonding
        note("connected; discovering services")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        note("connect failed: \(Self.describe(error))")
        fail(error?.localizedDescription ?? "Couldn't connect.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        note("disconnected: \(Self.describe(error))")
        if case .failed = state { return }
        state = .idle
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        note("services \(Self.describe(error)): \(services.map { Self.short($0.uuid) })")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let gatt = StrapGATT.forFamily(family)
        let notify = Set((gatt.notify + [StrapGATT.heartRateMeasurement]).map { CBUUID(string: $0) })
        let characteristics = service.characteristics ?? []
        note("characteristics of \(Self.short(service.uuid)) \(Self.describe(error)): "
            + characteristics.map { "\(Self.short($0.uuid))[\(Self.describe($0.properties))]" }.joined(separator: " "))
        for c in characteristics {
            if notify.contains(c.uuid) { peripheral.setNotifyValue(true, for: c) }
            if c.uuid == CBUUID(string: gatt.commandWrite) { commandCharacteristic = c }
        }
        guard service.uuid == CBUUID(string: gatt.service), commandCharacteristic != nil else { return }
        // The bond write. WHOOP 4: a battery read. 5/MG: the fixed client hello.
        note("bond write")
        write(family == .whoop4 ? sharedFrame(.getBatteryLevel) : CommandEncoder<Whoop5Generation>.clientHello)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        note("notify \(Self.short(characteristic.uuid)) \(characteristic.isNotifying ? "on" : "off") \(Self.describe(error))")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        note("tx \(Self.short(characteristic.uuid)) result \(Self.describe(error))")
        if let error {
            return fail("Write failed: \(error.localizedDescription). Unpair the strap in the official WHOOP app, close it, then try again.")
        }
        guard state == .bonding, let history else { return }
        state = .syncing
        note("bonded; sending connect sequence")
        for frame in connectFrames(unixSeconds: UInt32(Date.now.timeIntervalSince1970)) { write(frame) }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            note("history offload requested")
            write(await history.startFrame())
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else {
            note("rx \(Self.short(characteristic.uuid)) empty \(Self.describe(error))")
            return
        }
        let bytes = [UInt8](data)
        note("rx \(Self.short(characteristic.uuid))\(error == nil ? "" : " \(Self.describe(error))")", bytes: bytes)
        if characteristic.uuid == CBUUID(string: StrapGATT.heartRateMeasurement) {
            if let hr = HeartRateMeasurement(bytes, family: family), hr.contact != .notDetected { liveBPM = hr.bpm }
            return
        }
        incoming.yield(bytes)
    }
}
