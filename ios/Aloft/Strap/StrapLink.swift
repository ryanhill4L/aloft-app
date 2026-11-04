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
    typealias State = BandMachine.State

    struct Found: Identifiable, Equatable {
        let id: UUID
        let name: String
        let family: StrapFamily
        let rssi: Int
    }

    private var machine = BandMachine()
    private var timerID = 0
    private var findWhenPowered = false
    private var helloSent = false
    private var pendingNotifies: [CBCharacteristic] = []
    private var batteryCharacteristic: CBCharacteristic?
    private var connectedAt: Date?
    private var probeNotedMissing = false
    private let memoryKey = "aloft.strap.id"

    var state: State { machine.state }
    var canCommand: Bool { machine.canCommand && commandCharacteristic != nil }
    var statusLine: String { machine.statusLine }
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
    private var notedHistoryLayout = false
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
        if let saved = UserDefaults.standard.string(forKey: memoryKey) {
            machine.remembered = UUID(uuidString: saved)
        }
        if store == nil { note("store unavailable; history will not be acked") }
        Task { [weak self] in
            await self?.reloadEvents()
            for await bytes in stream { await self?.handle(bytes) }
        }
    }

    /// Creates the central lazily so the Bluetooth prompt appears on Find,
    /// not at launch. A found strap is connected from here; the Log tab does
    /// not have a second tap.
    func find() {
        guard central != nil else {
            note("creating central")
            findWhenPowered = true
            central = CBCentralManager(delegate: self, queue: .main)
            return
        }
        guard central?.state == .poweredOn else {
            let event: BandMachine.Event = central?.state == .unauthorized ? .notAllowed : .poweredOff
            apply(machine.send(event))
            return
        }
        found = []
        apply(machine.send(.find))
    }

    func retry() { find() }

    func connect(_ strap: Found) {
        family = strap.family
        apply(machine.send(.choose(strap.id)))
    }

    func disconnect() { apply(machine.send(.disconnect)) }

    /// Drops the link and the remembered peripheral, so the next Find can
    /// pick a different strap.
    func forget() { apply(machine.send(.forget)) }

    private func readyToSend() -> Bool {
        guard canCommand else {
            note("command skipped: \(state)")
            return false
        }
        return true
    }

    private func apply(_ outcome: BandMachine.Outcome) {
        note(outcome.log)
        if case let .failed(reason) = machine.state { lastError = reason }
        if let id = machine.remembered?.uuidString {
            UserDefaults.standard.set(id, forKey: memoryKey)
        }
        if outcome.clearMemory {
            UserDefaults.standard.removeObject(forKey: memoryKey)
        }
        if outcome.cancelTimers { timerID += 1 }
        if outcome.cancel, let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }
        if outcome.stopScan { central?.stopScan() }
        if outcome.scan { scan() }
        if outcome.retrieve { retrieve() }
        if outcome.connect { connectCurrent() }
        if outcome.subscribe { subscribeAndStart() }
        if let seconds = outcome.schedulePairWait { schedule(seconds, .pairWaitElapsed) }
        if outcome.awaitingPairing {
            let since = millisecondsSinceConnect().map { " \($0)ms since connect" } ?? ""
            note("\(StrapLines.waitingForPairing)\(since)")
            watchForEncryption(generation: timerID)
        }
        if outcome.retryHello { retryHello() }
        if let seconds = outcome.scheduleBackoff { schedule(seconds, .backoffElapsed) }
    }

    private func schedule(_ seconds: Int, _ event: BandMachine.Event) {
        timerID += 1
        let id = timerID
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, id == self.timerID else { return }
            self.apply(self.machine.send(event))
        }
    }

    /// Reads the standard battery characteristic until it answers or the wait
    /// ends. A success means that characteristic is readable. On build 4 it
    /// answered while the same hello, retried, still got ATT 5, so it is not
    /// proof the strap will accept a command.
    private func watchForEncryption(generation: Int) {
        guard family == .whoop5 else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(BandMachine.encryptionProbeSeconds))
                guard let self, generation == self.timerID else { return }
                guard self.state == .pairing, self.machine.waitingForPairing, !self.machine.helloRetried else { return }
                self.probeEncryption()
            }
        }
    }

    private func probeEncryption() {
        guard let peripheral, let batteryCharacteristic else {
            if !probeNotedMissing {
                probeNotedMissing = true
                note("encryption probe skipped: no battery characteristic")
            }
            return
        }
        note("encryption probe: read 2A19")
        peripheral.readValue(for: batteryCharacteristic)
    }

    private func retryHello() {
        guard state == .pairing, commandCharacteristic != nil else { return }
        note(family == .whoop5 ? "hello retry withResponse" : "bond retry withResponse")
        write(family == .whoop4 ? sharedFrame(.getBatteryLevel) : CommandEncoder<Whoop5Generation>.clientHello)
    }

    private func millisecondsSinceConnect() -> Int? {
        guard let connectedAt else { return nil }
        return Int(Date.now.timeIntervalSince(connectedAt) * 1000)
    }

    #if DEBUG
    /// Drives the build-4 refusal, without opening Bluetooth, so the Log tab
    /// can show it in the Simulator.
    func previewPairingWait() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        _ = machine.send(.find)
        _ = machine.send(.discovered(id))
        _ = machine.send(.connected)
        _ = machine.send(.authRefused)
        _ = machine.send(.encryptionUp)
        let outcome = machine.send(.offWrist)
        lastError = BandMachine.offWrist
        note(StrapLines.waitingForPairing)
        note("battery read ok")
        note(StrapLines.encryptedButRefused)
        note(outcome.log)
    }
    #endif

    private func scan() {
        let services = [CBUUID(string: StrapGATT.whoop4.service), CBUUID(string: StrapGATT.whoop5.service)]
        central?.scanForPeripherals(withServices: services)
        note("scan started")
    }

    /// Remembered strap first: a connected one, then one iOS still knows.
    /// A miss falls through to a scan.
    private func retrieve() {
        guard let id = machine.remembered, let central else {
            apply(machine.send(.retrieved(false)))
            return
        }
        let services = [CBUUID(string: StrapGATT.whoop5.service), CBUUID(string: StrapGATT.whoop4.service)]
        let connected = central.retrieveConnectedPeripherals(withServices: services)
        let known = central.retrievePeripherals(withIdentifiers: [id])
        guard let match = (connected + known).first(where: { $0.identifier == id }) else {
            note("remembered strap not retrieved")
            apply(machine.send(.retrieved(false)))
            return
        }
        peripherals[id] = match
        note("retrieved \(id)")
        apply(machine.send(.retrieved(true)))
    }

    private func connectCurrent() {
        guard let id = machine.remembered, let p = peripherals[id] else {
            note("connect skipped: no peripheral")
            return
        }
        helloSent = false
        pendingNotifies = []
        commandCharacteristic = nil
        batteryCharacteristic = nil
        probeNotedMissing = false
        switch family {
        case .whoop4: whoop4Encoder = CommandEncoder()
        case .whoop5: whoop5Encoder = CommandEncoder()
        }
        peripheral = p
        p.delegate = self
        reassembler = Reassembler(family: family)
        notedHistoryLayout = false
        if let store { history = HistorySync(family: family, store: store) }
        central?.connect(p)
        note("connecting \(id)")
    }

    /// Puffin notifies wait until the hello write is accepted. Subscribing
    /// them first is refused (authentication/encryption insufficient) and
    /// wedges the bond. noop BLEManager retains fd4b0003/4/5/7 here and
    /// subscribes them only from the confirmed-write callback.
    private func subscribeAndStart() {
        guard let peripheral else { return }
        for c in pendingNotifies {
            peripheral.setNotifyValue(true, for: c)
        }
        guard let history else { return }
        note("paired; sending connect sequence")
        for frame in connectFrames(unixSeconds: UInt32(Date.now.timeIntervalSince1970)) { write(frame) }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard self.state == .ready else { return }
            note("history offload requested")
            write(await history.startFrame())
        }
    }

    /// 5/MG command 19. WHOOP 4 uses command 79. Each builder exists only on
    /// that generation's encoder.
    func buzz() {
        guard readyToSend() else { return }
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
        guard readyToSend() else { return }
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
        guard readyToSend() else { return }
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
        guard readyToSend() else { return }
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
            if frame.type == .historicalData, !notedHistoryLayout {
                notedHistoryLayout = true
                note("history layout \(frame.sequence)")
            }
            let (outcome, ack) = await history.receive(frame, now: Int64(Date.now.timeIntervalSince1970))
            switch outcome {
            case let .ack(rows, trim):
                if let ack { write(ack) }
                lastSync = .now
                note("chunk stored: \(rows) rows, trim \(trim), acked")
            case .stalled:
                lastError = "A history write failed. Nothing more is acked until reconnect."
                note(lastError ?? "")
            case .complete:
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
        case .poweredOn:
            if findWhenPowered {
                findWhenPowered = false
                found = []
                apply(machine.send(.find))
            } else {
                apply(machine.send(.poweredOn))
            }
        case .unauthorized:
            apply(machine.send(.notAllowed))
        case .poweredOff:
            apply(machine.send(.poweredOff))
        default:
            break
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
        self.family = family
        apply(machine.send(.discovered(strap.id)))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedAt = .now
        note("connected; discovering services")
        let outcome = machine.send(.connected)
        apply(outcome)
        guard state == .pairing else { return }
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        note("connect failed: \(Self.describe(error))")
        apply(machine.send(.linkDropped))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let ns = error.map { $0 as NSError }
        // Read this before linkDropped clears it. A nil error is what our own cancel produces.
        let localCancel = machine.expectingDrop
        note(StrapLines.disconnected(
            domain: ns.map(\.domain),
            code: ns.map(\.code),
            millisecondsSinceConnect: millisecondsSinceConnect(),
            localCancel: localCancel
        ))
        commandCharacteristic = nil
        helloSent = false
        batteryCharacteristic = nil
        apply(machine.send(.linkDropped))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        note("services \(Self.describe(error)): \(services.map { Self.short($0.uuid) })")
        if services.contains(where: { $0.uuid == CBUUID(string: StrapGATT.whoop4.service) }) {
            family = .whoop4
        } else if services.contains(where: { $0.uuid == CBUUID(string: StrapGATT.whoop5.service) }) {
            family = .whoop5
        }
        reassembler = Reassembler(family: family)
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let gatt = StrapGATT.forFamily(family)
        let puffin = Set(gatt.notify.map { CBUUID(string: $0) })
        let heart = CBUUID(string: StrapGATT.heartRateMeasurement)
        let characteristics = service.characteristics ?? []
        note("characteristics of \(Self.short(service.uuid)) \(Self.describe(error)): "
            + characteristics.map { "\(Self.short($0.uuid))[\(Self.describe($0.properties))]" }.joined(separator: " "))
        let battery = CBUUID(string: StrapGATT.batteryLevel)
        for c in characteristics {
            if c.uuid == heart { peripheral.setNotifyValue(true, for: c) }
            if c.uuid == battery { batteryCharacteristic = c }
            if puffin.contains(c.uuid), !pendingNotifies.contains(where: { $0.uuid == c.uuid }) {
                pendingNotifies.append(c)
            }
            if c.uuid == CBUUID(string: gatt.commandWrite) { commandCharacteristic = c }
        }
        guard state == .pairing, commandCharacteristic != nil, !helloSent else { return }
        helloSent = true
        // 5/MG: the hello write, with a response, is what asks iOS to pair.
        // Puffin notifies stay off until that write is accepted.
        note(family == .whoop5 ? "hello write withResponse" : "bond write withResponse")
        write(family == .whoop4 ? sharedFrame(.getBatteryLevel) : CommandEncoder<Whoop5Generation>.clientHello)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        note("notify \(Self.short(characteristic.uuid)) \(characteristic.isNotifying ? "on" : "off") \(Self.describe(error))")
        if let error, Self.isPairingRefusal(error) {
            apply(machine.send(.authRefused))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        note("tx \(Self.short(characteristic.uuid)) result \(Self.describe(error))")
        guard state == .pairing else { return }
        if let error {
            if Self.isPairingRefusal(error) {
                let code = (error as NSError).code
                if StrapLines.refusedAfterEncrypt(waiting: machine.waitingForPairing, retriedHello: machine.helloRetried, code: code) {
                    note(StrapLines.encryptedButRefused)
                    apply(machine.send(.offWrist))
                } else {
                    apply(machine.send(.authRefused))
                }
            } else {
                lastError = "Write failed: \(error.localizedDescription)"
                note(lastError ?? "")
                apply(machine.send(.authRefused))
            }
            return
        }
        apply(machine.send(.paired))
    }

    private static func isPairingRefusal(_ error: Error) -> Bool {
        let ns = error as NSError
        return BandMachine.isPairingRefusal(domain: ns.domain, code: ns.code)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == CBUUID(string: StrapGATT.batteryLevel) {
            // Build 4: this read succeeded and the retried hello still got ATT 5.
            // Answered means "try the hello once more," not "the bond is good."
            if error == nil, characteristic.value != nil,
               family == .whoop5, state == .pairing, machine.waitingForPairing, !machine.helloRetried {
                note("battery read ok")
                apply(machine.send(.encryptionUp))
            } else if state == .pairing, machine.waitingForPairing {
                note("encryption probe \(Self.describe(error))")
            }
            return
        }
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
