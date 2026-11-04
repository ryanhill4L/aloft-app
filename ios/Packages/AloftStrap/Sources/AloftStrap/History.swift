// History offload, rewritten from NOOP's Strand/Collect/Backfiller.swift and
// WhoopProtocol/HistoricalStreams.swift (ryanbr/noop@2a1de760). Offsets are
// WHOOP 4 offsets; `Frame.offset` adds four for 5/MG.

public enum HistoryMarker: Sendable, Equatable {
    case start
    /// `endData` is acked verbatim. On WHOOP 4 it can overlap the frame's own
    /// CRC-32 trailer; copy by absolute offset, never rebuild it.
    case end(trim: UInt32, endData: [UInt8])
    case complete
}

extension Frame {
    public var historyMarker: HistoryMarker? {
        guard type == .metadata else { return nil }
        switch bytes[offset(6)] {
        case 1: return .start
        case 3: return .complete
        case 2:
            let start = offset(17)
            guard bytes.count >= start + 8 else { return nil }
            return .end(trim: bytes.u32(at: start), endData: Array(bytes[start..<start + 8]))
        default: return nil
        }
    }

    /// Heart rate, R-R, and motion from one type-47 record. R-R values in
    /// history are already milliseconds on both families. Motion offsets are
    /// absolute per generation: do not add four to a WHOOP 4 gravity offset
    /// and call it 5/MG. Unknown layouts yield nothing.
    public func historicalSamples() -> SampleBatch {
        guard type == .historicalData else { return SampleBatch() }
        let layout: (time: Int, hr: Int, count: Int, rr: Int, motion: MotionLayout?)
        switch (family, sequence) {
        case (.whoop4, 5), (.whoop4, 7), (.whoop4, 9):
            layout = (11, 21, 22, 23, nil)
        case (.whoop4, 12), (.whoop4, 24):
            layout = (11, 21, 22, 23, MotionLayout(x: 40, y: 44, z: 48, dynamic: nil, sleepByte: nil))
        case (.whoop5, 18):
            layout = (15, 22, 23, 24, MotionLayout(x: 45, y: 49, z: 53, dynamic: 41, sleepByte: 81))
        default:
            return SampleBatch()
        }
        guard bytes.count >= layout.count + 1 + 4 else { return SampleBatch() }
        let ms = Int64(bytes.u32(at: layout.time)) * 1000
        var batch = SampleBatch()
        if bytes[layout.hr] > 0 {
            batch.heartRate.append(HeartRateSample(timestampMs: ms, bpm: Int(bytes[layout.hr])))
        }
        let count = min(Int(bytes[layout.count]), 4)
        for i in 0..<count {
            let at = layout.rr + 2 * i
            guard at + 1 < bytes.count - 4 else { break }
            let value = bytes.u16(at: at)
            if value > 0 {
                batch.rr.append(RRInterval(timestampMs: ms, milliseconds: Int(value)))
            }
        }
        if let motion = layout.motion, let sample = motionSample(ms: ms, layout: motion) {
            batch.motion.append(sample)
        }
        return batch
    }

    /// A field that ends before the CRC-32 trailer.
    private func fits(_ offset: Int, _ length: Int) -> Bool {
        offset >= 0 && offset + length <= bytes.count - 4
    }

    private func motionSample(ms: Int64, layout: MotionLayout) -> MotionSample? {
        var x: Int?
        var y: Int?
        var z: Int?
        var dynamic: Int?
        if fits(layout.x, 4), fits(layout.y, 4), fits(layout.z, 4),
           let gx = bytes.f32(at: layout.x), let gy = bytes.f32(at: layout.y), let gz = bytes.f32(at: layout.z) {
            let magnitude = (gx * gx + gy * gy + gz * gz).squareRoot()
            if magnitude >= 0.25, magnitude <= 4 {
                x = milliG(gx)
                y = milliG(gy)
                z = milliG(gz)
                if let at = layout.dynamic, fits(at, 4), let value = bytes.f32(at: at), value >= 0, value <= 8 {
                    dynamic = milliG(value)
                }
            }
        }
        var sleep: UInt8?
        if let at = layout.sleepByte, fits(at, 1) {
            sleep = bytes[at]
        }
        guard x != nil || sleep != nil else { return nil }
        return MotionSample(timestampMs: ms, xMilliG: x, yMilliG: y, zMilliG: z, dynamicMilliG: dynamic, sleepByte: sleep)
    }
}

/// Absolute frame offsets for the gravity block. `dynamic` and `sleepByte`
/// exist on WHOOP 5 v18 only.
private struct MotionLayout {
    var x: Int
    var y: Int
    var z: Int
    var dynamic: Int?
    var sleepByte: Int?
}

private func milliG(_ g: Float) -> Int {
    Int((Double(g) * 1_000).rounded())
}

/// What happened when a frame reached the history state machine.
public enum HistoryOutcome: Sendable, Equatable {
    case collected
    /// The chunk is durable; send this ack frame.
    case ack(rowsWritten: Int, trim: UInt32)
    /// A write failed this session. Nothing is acked until reconnect, so the
    /// strap cannot trim past rows the phone never stored.
    case stalled
    case complete
    case ignored
}

/// Collects records between markers and decides when an ack is allowed.
/// Pure state; the caller owns the store write and the BLE write.
public struct HistorySession: Sendable {
    public static let earliestPlausibleUnix: Int64 = 1_700_000_000

    private var chunk: [Frame] = []
    private var open = true
    public private(set) var stalled = false

    public init() {}

    public enum Step: Sendable, Equatable {
        case none
        case complete
        /// Persist `batch`, then call `persisted` or `failed`.
        case persist(batch: SampleBatch, trim: UInt32, endData: [UInt8])
        /// Not a history record. Event frames used to land in the open chunk
        /// and disappear when the chunk was decoded.
        case ignored
    }

    public mutating func receive(_ frame: Frame, now: Int64) -> Step {
        if frame.type == .event { return .ignored }
        switch frame.historyMarker {
        case .start:
            chunk.removeAll()
            open = true
            return .none
        case .complete:
            chunk.removeAll()
            open = false
            return .complete
        case let .end(trim, endData):
            let frames = chunk
            chunk.removeAll()
            var batch = SampleBatch()
            for record in frames {
                let samples = record.historicalSamples()
                batch.heartRate += samples.heartRate.filter { Self.plausible($0.timestampMs, now: now) }
                batch.rr += samples.rr.filter { Self.plausible($0.timestampMs, now: now) }
                batch.motion += samples.motion.filter { Self.plausible($0.timestampMs, now: now) }
            }
            return .persist(batch: batch, trim: trim, endData: endData)
        case nil:
            if open { chunk.append(frame) }
            return .none
        }
    }

    public mutating func markFailed() { stalled = true }

    /// Timeouts never authorize an ack; they only drop the open chunk.
    public mutating func timedOut() { chunk.removeAll() }

    static func plausible(_ ms: Int64, now: Int64) -> Bool {
        let s = ms / 1000
        return s >= earliestPlausibleUnix && s <= now + 86_400
    }
}

/// Wires a session to the store: insert, fold, then and only then ack.
public actor HistorySync {
    private var session = HistorySession()
    private var outbound: Outbound
    private let store: StrapStore

    public init(family: StrapFamily, store: StrapStore) {
        self.outbound = Outbound(family: family)
        self.store = store
    }

    public func startFrame() -> [UInt8] { outbound.startHistory() }

    /// Returns the outcome and, for `.ack`, the frame to write.
    public func receive(_ frame: Frame, now: Int64) async -> (HistoryOutcome, [UInt8]?) {
        switch session.receive(frame, now: now) {
        case .none:
            return (.collected, nil)
        case .ignored:
            return (.ignored, nil)
        case .complete:
            return (.complete, nil)
        case let .persist(batch, trim, endData):
            if session.stalled { return (.stalled, nil) }
            do {
                let written = try await store.insert(batch)
                return (.ack(rowsWritten: written, trim: trim), outbound.ackHistory(endData: endData))
            } catch {
                session.markFailed()
                return (.stalled, nil)
            }
        }
    }
}

/// The shared-command encoder for whichever generation connected. Alarm and
/// haptic commands are not sent from here.
private struct Outbound: Sendable {
    private var whoop4 = CommandEncoder<Whoop4Generation>()
    private var whoop5 = CommandEncoder<Whoop5Generation>()
    private let family: StrapFamily

    init(family: StrapFamily) { self.family = family }

    mutating func startHistory() -> [UInt8] {
        switch family {
        case .whoop4: return whoop4.startHistory()
        case .whoop5: return whoop5.startHistory()
        }
    }

    mutating func ackHistory(endData: [UInt8]) -> [UInt8] {
        switch family {
        case .whoop4: return whoop4.ackHistory(endData: endData)
        case .whoop5: return whoop5.ackHistory(endData: endData)
        }
    }
}
