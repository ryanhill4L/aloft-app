import Testing
@testable import AloftStrap

/// Alarm and haptic frames, command responses, and strap events.
///
/// 5/MG is the primary path (Ryan's strap). The golden frame is
/// `DeviceFamilyFramingTests.testPuffinAlarmFramesMatchKotlinParityGoldens`
/// in ryanbr/noop@2a1de760, line 349. The WHOOP 4 bytes are the 7:00 capture
/// in bWanShiTong/reverse-engineering-whoop-post README.md line 114
/// (unlicensed; the byte string only). Response payloads are the byte forms
/// in StrandTests/AlarmReadbackDecodeTests.swift (`responseFrame`, lines 20-22,
/// and the payloads at lines 28, 55, and 226).
@Suite struct AlarmTests {
    static let mgGolden = [UInt8](hex: "aa011c000001e381230142040100f15365be0f2f980000000000000000071e00392f2ac9")!
    static let whoop4Set = [UInt8](hex: "aa100057236d4201d036656600000000f62deb81")!
    static let slot1 = Whoop5Generation.AlarmSlot(rawValue: 1)!

    @Test func mgSetAlarmMatchesNoopGolden() {
        var enc = CommandEncoder<Whoop5Generation>()
        let fraction = CommandEncoder<Whoop5Generation>.fractionTicks(millisecond: 123)
        #expect(fraction == 4030)
        let frame = enc.setAlarm(slot: Self.slot1, unixSeconds: 1_700_000_000, fractionTicks: fraction)
        #expect(frame == Self.mgGolden)
        #expect(frame.count == 36)
    }

    @Test func whoop4SetAlarmMatchesCapture() {
        let epoch: UInt32 = 0x6665_36D0
        let body = CommandEncoder<Whoop4Generation>.setAlarmBody(unixSeconds: epoch)
        #expect(body == [0x01, 0xD0, 0x36, 0x65, 0x66, 0x00, 0x00, 0x00, 0x00])
        let frame = Frame.command(.whoop4, sequence: 0x6D, command: StrapCommand.setAlarmTime.rawValue, body: body)
        #expect(frame == Self.whoop4Set)
    }

    @Test func mgPayloads() {
        let set = CommandEncoder<Whoop5Generation>.setAlarmBody(slot: Self.slot1, unixSeconds: 1_700_000_000, fractionTicks: 4030)
        #expect(set == [UInt8](hex: "040100f15365be0f2f980000000000000000071e00")!)
        #expect(set.count == 21)
        let slot3 = Whoop5Generation.AlarmSlot(rawValue: 3)!
        #expect(CommandEncoder<Whoop5Generation>.getAlarmBody(slot: slot3) == [0x04, 0x03])
        #expect(CommandEncoder<Whoop5Generation>.runAlarmBody(slot: Self.slot1) == [0x02, 0x01])
        #expect(CommandEncoder<Whoop5Generation>.disableAlarmBody(slot: Whoop5Generation.AlarmSlot(rawValue: 2)!) == [0x02, 0x02])
        #expect(CommandEncoder<Whoop5Generation>.disableAllAlarmsBody() == [0x02, 0xFF])
        #expect(CommandEncoder<Whoop5Generation>.buzzBody(repeats: 1) == [0x01, 0x2F, 0x98, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        #expect(CommandEncoder<Whoop5Generation>.buzzBody(repeats: 2).last == 1)
        #expect(CommandEncoder<Whoop5Generation>.buzzBody(repeats: 5).last == 4)
        #expect(CommandEncoder<Whoop5Generation>.buzzBody(repeats: 8).last == 7)
        #expect(CommandEncoder<Whoop5Generation>.buzzBody(repeats: 0).last == 0)
        #expect(CommandEncoder<Whoop5Generation>.buzzBody(repeats: 99).last == 7)
        #expect(CommandEncoder<Whoop5Generation>.stopHapticsBody() == [0x01])
        #expect(Whoop5Generation.AlarmSlot(rawValue: 0) == nil)
        #expect(Whoop5Generation.AlarmSlot(rawValue: 7) == nil)
        #expect(Whoop5Generation.AlarmSlot(rawValue: 255) == nil)
    }

    @Test func whoop4Payloads() {
        #expect(CommandEncoder<Whoop4Generation>.setAlarmBody(unixSeconds: 1_781_912_880) == [0x01, 0x30, 0xD5, 0x35, 0x6A, 0x00, 0x00, 0x00, 0x00])
        #expect(CommandEncoder<Whoop4Generation>.setAlarmBody(unixSeconds: 0x1122_3344) == [0x01, 0x44, 0x33, 0x22, 0x11, 0x00, 0x00, 0x00, 0x00])
        #expect(CommandEncoder<Whoop4Generation>.getAlarmBody() == [0x01])
        #expect(CommandEncoder<Whoop4Generation>.runAlarmBody() == [0x01])
        #expect(CommandEncoder<Whoop4Generation>.disableAlarmBody() == [0x01])
        #expect(CommandEncoder<Whoop4Generation>.runHapticsBody() == [0x02, 0x03, 0x00, 0x00, 0x00])
        #expect(CommandEncoder<Whoop4Generation>.stopHapticsBody() == [0x00])
    }

    @Test func mgFramesUseTheRightOpcodes() throws {
        var enc = CommandEncoder<Whoop5Generation>()
        let frames = [
            enc.getAlarm(slot: Self.slot1),
            enc.runAlarm(slot: Self.slot1),
            enc.disableAlarm(slot: Self.slot1),
            enc.disableAllAlarms(),
            enc.buzz(),
            enc.stopHaptics(),
        ]
        let parsed = try frames.map { try Frame(family: .whoop5, bytes: $0) }
        #expect(parsed.map(\.command) == [
            StrapCommand.getAlarmTime.rawValue,
            StrapCommand.runAlarm.rawValue,
            StrapCommand.disableAlarm.rawValue,
            StrapCommand.disableAlarm.rawValue,
            StrapCommand.Whoop5.buzz.rawValue,
            StrapCommand.stopHaptics.rawValue,
        ])
        #expect(parsed.map(\.sequence) == [1, 2, 3, 4, 5, 6])
        #expect(Array(parsed[3].bytes[11..<13]) == [0x02, 0xFF])
        #expect(Array(parsed[4].bytes[11..<23]) == CommandEncoder<Whoop5Generation>.buzzBody(repeats: 1))
        #expect(parsed[5].bytes[11] == 0x01)
    }

    @Test func whoop4FramesUseTheRightOpcodes() throws {
        var enc = CommandEncoder<Whoop4Generation>()
        let frames = [
            enc.getAlarm(),
            enc.runAlarm(),
            enc.disableAlarm(),
            enc.runHaptics(),
            enc.stopHaptics(),
        ]
        let parsed = try frames.map { try Frame(family: .whoop4, bytes: $0) }
        #expect(parsed.map(\.command) == [
            StrapCommand.getAlarmTime.rawValue,
            StrapCommand.runAlarm.rawValue,
            StrapCommand.disableAlarm.rawValue,
            StrapCommand.Whoop4.runHapticsPattern.rawValue,
            StrapCommand.stopHaptics.rawValue,
        ])
        #expect(Array(parsed[3].bytes[7..<12]) == [0x02, 0x03, 0x00, 0x00, 0x00])
        #expect(parsed[4].bytes[7] == 0x00)
    }

    /// 5/MG type 36: command, origin, result, and the first body byte are
    /// offsets 10...13.
    @Test func mgResponseWindowIsOffsets10Through13() throws {
        let raw = Frame.encode(.whoop5, type: 36, sequence: 0x29, command: 66, body: [0x42, 0x03, 0x04, 0x01])
        let frame = try Frame(family: .whoop5, bytes: raw)
        #expect(Array(frame.bytes[10...13]) == [66, 0x42, 0x03, 0x04])
        #expect(frame.commandResponse == CommandResponse(command: 66, originSequence: 0x42, result: 0x03, body: [0x04, 0x01, 0x00]))
        #expect(frame.commandResponse?.resultName == "unsupported")
    }

    /// Byte forms from AlarmReadbackDecodeTests.responseFrame. WHOOP 4 keeps
    /// the same four fields at offsets 6...9.
    @Test func whoop4ResponsesUseAlarmReadbackBytes() throws {
        let mirror = response(.whoop4, cmd: 67, result: 1, payload: [0x01, 0x30, 0xD5, 0x35, 0x6A, 0x00, 0x00, 0x00, 0x00])
        let readback = response(.whoop4, cmd: 67, result: 1, payload: [0x01, 0x01, 0xD0, 0x72, 0x8E, 0x6A, 0x00, 0x00, 0x04, 0x00, 0x20])
        let rejected = response(.whoop4, cmd: 66, result: 0x03, payload: [])
        let mirrorFrame = try Frame(family: .whoop4, bytes: mirror)
        #expect(Array(mirrorFrame.bytes[6...9]) == [67, 0x42, 0x01, 0x01])
        #expect(mirrorFrame.commandResponse?.body == [0x01, 0x30, 0xD5, 0x35, 0x6A, 0x00, 0x00, 0x00, 0x00])
        #expect(try Frame(family: .whoop4, bytes: readback).commandResponse?.body == [0x01, 0x01, 0xD0, 0x72, 0x8E, 0x6A, 0x00, 0x00, 0x04, 0x00, 0x20])
        let rejectedFrame = try Frame(family: .whoop4, bytes: rejected)
        #expect(rejectedFrame.commandResponse == CommandResponse(command: 66, originSequence: 0x42, result: 0x03, body: []))
        #expect(rejectedFrame.commandResponse?.resultName == "unsupported")
    }

    @Test func eventsDecodeOnBothGenerations() throws {
        let ts: UInt32 = 1_700_000_123
        let named: [(UInt8, StrapEvent.Name)] = [
            (9, .wristOn), (10, .wristOff), (14, .doubleTap),
            (56, .alarmSet), (57, .alarmFired), (58, .alarmFiredByApp),
            (60, .hapticsFired), (100, .hapticsFired),
        ]
        for family in [StrapFamily.whoop5, .whoop4] {
            for (id, name) in named {
                let raw = Frame.encode(family, type: 48, sequence: 1, command: id, body: [0x00] + le32(ts))
                let frame = try Frame(family: family, bytes: raw)
                #expect(frame.bytes[frame.offset(6)] == id)
                #expect(frame.bytes.u32(at: frame.offset(8)) == ts)
                #expect(frame.strapEvent == StrapEvent(id: id, unixSeconds: ts))
                #expect(frame.strapEvent?.name == name)
            }
            let unknown = try Frame(family: family, bytes: Frame.encode(family, type: 48, sequence: 1, command: 42, body: [0x00] + le32(ts)))
            #expect(unknown.strapEvent?.id == 42)
            #expect(unknown.strapEvent?.name == nil)
            #expect(unknown.strapEvent?.label == "event 42")
        }
    }

    /// `[type][seq][cmd][origin][result][payload…]`, matching
    /// AlarmReadbackDecodeTests.responseFrame (seq 0x29, origin 0x42).
    private func response(_ family: StrapFamily, cmd: UInt8, result: UInt8, payload: [UInt8]) -> [UInt8] {
        Frame.encode(family, type: 36, sequence: 0x29, command: cmd, body: [0x42, result] + payload)
    }
}
