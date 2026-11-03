import Testing
@testable import AloftStrap

/// Vectors come from NOOP's public tests (ryanbr/noop@2a1de760) or were
/// built with the same algorithm and cross-checked with zlib.
@Suite struct FramingTests {
    @Test func crcCheckValues() {
        let check = Array("123456789".utf8)
        #expect(CRC.crc8(check) == 0xF4)
        #expect(CRC.crc16(check) == 0x4B37)
        #expect(CRC.crc32(check) == 0xCBF4_3926)
        #expect(CRC.crc16([]) == 0xFFFF)
        #expect(CRC.crc16([0x01, 0x04, 0x02, 0xFF, 0xFF]) == 0x80B8)
        #expect(CRC.crc32([]) == 0)
    }

    @Test(arguments: [
        (StrapFamily.whoop4, UInt8(8), UInt8(14), [UInt8(1)], "aa0800a823080e016c935474"),
        (.whoop4, 7, 14, [0], "aa0800a823070e00c7e40f08"),
        (.whoop4, 1, 26, [0], "aa0800a823011a00204f2c22"),
        (.whoop5, 1, 0x91, [1], "aa0108000001e67123019101363e5c8d"),
        (.whoop5, 1, 0x13, [0x01, 0x2F, 0x98] + [UInt8](repeating: 0, count: 9), "aa0114000001e1e1230113012f980000000000000000000098cb83a5"),
        (.whoop5, 1, 69, [0x02, 0xFF], "aa010c000001e74123014502ff000000267ffc4f"),
        (.whoop5, 0, 23, [0x01, 0x41, 0xB6, 0x01, 0x00, 0x10, 0x00, 0x00, 0x00], "aa0110000001e0d12300170141b6010010000000667da4fb"),
    ])
    func commandFrames(family: StrapFamily, seq: UInt8, cmd: UInt8, body: [UInt8], hex: String) throws {
        let built = Frame.command(family, sequence: seq, command: cmd, body: body)
        #expect(built == [UInt8](hex: hex))
        _ = try Frame(family: family, bytes: built)
    }

    @Test func clientHelloIsAValidFrame() throws {
        let frame = try Frame(family: .whoop5, bytes: CommandEncoder<Whoop5Generation>.clientHello)
        #expect(frame.command == StrapCommand.getHello.rawValue)
    }

    @Test func verifyRejectsInOrder() throws {
        let good = [UInt8](hex: "aa1800ff28020f3de10128663c0000000000000000000000da855212")!
        let frame = try Frame(family: .whoop4, bytes: good)
        #expect(frame.type == .realtimeData)

        #expect(throws: FrameError.noStartByte) { try Frame(family: .whoop4, bytes: [0x00] + good.dropFirst()) }
        #expect(throws: FrameError.tooShort) { try Frame(family: .whoop4, bytes: Array(good.prefix(8))) }
        #expect(throws: FrameError.lengthMismatch) { try Frame(family: .whoop4, bytes: good + [0]) }
        var badHeader = good
        badHeader[3] ^= 0xFF
        #expect(throws: FrameError.headerCRC) { try Frame(family: .whoop4, bytes: badHeader) }
        var badPayload = good
        badPayload[10] ^= 0x01
        #expect(throws: FrameError.payloadCRC) { try Frame(family: .whoop4, bytes: badPayload) }
    }

    @Test func commandResponseFields() throws {
        let w5 = try Frame(family: .whoop5, bytes: [UInt8](hex: "aa010c000001e74124070211223344557481f36e")!)
        #expect(w5.type == .commandResponse)
        let w4 = try Frame(family: .whoop4, bytes: [UInt8](hex: "aa10005724241a0000ff000000000000ac811df4")!)
        #expect(w4.command == StrapCommand.getBatteryLevel.rawValue)
    }

    @Test func reassemblesFragmentsAndResyncs() throws {
        let a = [UInt8](hex: "aa1800ff28020f3de10128663c0000000000000000000000da855212")!
        let b = [UInt8](hex: "aa10005724241a0000ff000000000000ac811df4")!
        // Junk, a stray 0xAA with a bad header CRC, then two frames split badly.
        let stream: [UInt8] = [0x01, 0x02, 0xAA, 0x05, 0x00, 0x99] + a + b
        var r = Reassembler(family: .whoop4)
        var out: [[UInt8]] = []
        for chunk in stride(from: 0, to: stream.count, by: 5).map({ Array(stream[$0..<min($0 + 5, stream.count)]) }) {
            out += r.append(chunk)
        }
        #expect(out == [a, b])
        #expect(r.droppedHeaders == 1)
    }

    @Test func connectSequenceSetsClockFirstOn5() throws {
        var enc = CommandEncoder<Whoop5Generation>()
        let frames = enc.connectSequence(unixSeconds: 1_780_000_000)
        let parsed = try frames.map { try Frame(family: .whoop5, bytes: $0) }
        #expect(parsed.map(\.command) == [StrapCommand.setClock.rawValue, StrapCommand.getClock.rawValue])
        #expect(parsed.map(\.sequence) == [1, 2])
    }
}
