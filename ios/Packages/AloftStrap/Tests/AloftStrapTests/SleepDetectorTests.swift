import Foundation
import Testing
@testable import AloftStrap

@Suite struct SleepDetectorTests {
    /// Aligned to a minute so each sample is its own epoch.
    static let base: Int64 = (1_700_000_000_000 / 60_000) * 60_000

    static func minute(_ index: Int, dynamic: Int, bpm: Int? = 52, rr: Int? = nil) -> (HeartRateSample?, RRInterval?, MotionSample) {
        let ts = base + Int64(index) * 60_000
        let hr = bpm.map { HeartRateSample(timestampMs: ts, bpm: $0) }
        let beat = rr.map { RRInterval(timestampMs: ts, milliseconds: $0) }
        let motion = MotionSample(timestampMs: ts, xMilliG: 0, yMilliG: 0, zMilliG: 1000, dynamicMilliG: dynamic, sleepByte: nil)
        return (hr, beat, motion)
    }

    static func night(_ rows: [(Int, Int, Int?)]) -> SleepNight {
        var hr: [HeartRateSample] = []
        var motion: [MotionSample] = []
        for (index, dynamic, bpm) in rows {
            let sample = minute(index, dynamic: dynamic, bpm: bpm)
            if let beat = sample.0 { hr.append(beat) }
            motion.append(sample.2)
        }
        return SleepDetector.detect(heartRate: hr, rr: [], motion: motion)
    }

    @Test func aStillStretchHasAnOnsetAndNoInventedWake() {
        let rows = (0..<30).map { ($0, 5, Optional(52)) }
        let night = Self.night(rows)
        #expect(night.onsetMs == Self.base)
        #expect(night.wakeMs == nil)
        #expect(night.efficiency == nil)
        #expect(night.asleepMs == 30 * 60_000)
        #expect(night.stages == nil)
        #expect(night.note == SleepNight.stageNote)
    }

    @Test func tenStillMinutesAreRequired() {
        let short = Self.night((0..<9).map { ($0, 5, Optional(52)) })
        #expect(short.onsetMs == nil)
        let exact = Self.night((0..<10).map { ($0, 5, Optional(52)) })
        #expect(exact.onsetMs == Self.base)
    }

    @Test func wakeIsFiveAwakeMinutesAndEfficiencyUsesInBed() {
        // 15 restless minutes in bed, 20 asleep, then 5 awake.
        var rows: [(Int, Int, Int?)] = (0..<15).map { ($0, 25, Optional(60)) }
        rows += (15..<35).map { ($0, 5, Optional(52)) }
        rows += (35..<40).map { ($0, 100, Optional(70)) }
        let night = Self.night(rows)
        #expect(night.inBedStartMs == Self.base)
        #expect(night.onsetMs == Self.base + 15 * 60_000)
        #expect(night.wakeMs == Self.base + 35 * 60_000)
        #expect(night.asleepMs == 20 * 60_000)
        #expect(night.inBedMs == Int64(35 * 60_000))
        #expect(night.efficiency == 20.0 / 35.0)
        #expect(night.stages == nil)
    }

    @Test func fourAwakeMinutesDoNotEndTheNight() {
        var rows: [(Int, Int, Int?)] = (0..<10).map { ($0, 5, Optional(52)) }
        rows += (10..<14).map { ($0, 100, Optional(70)) }
        rows += (14..<20).map { ($0, 5, Optional(52)) }
        let night = Self.night(rows)
        #expect(night.onsetMs == Self.base)
        #expect(night.wakeMs == nil)
    }

    @Test func aGapBreaksTheOnsetRun() {
        var rows: [(Int, Int, Int?)] = (0..<6).map { ($0, 5, Optional(52)) }
        rows += (10..<16).map { ($0, 5, Optional(52)) }
        #expect(Self.night(rows).onsetMs == nil)
    }

    @Test func beatIntervalsStandInWhenHeartRateIsMissing() {
        let ts = (0..<12).map { Self.base + Int64($0) * 60_000 }
        let motion = ts.map {
            MotionSample(timestampMs: $0, xMilliG: 0, yMilliG: 0, zMilliG: 1000, dynamicMilliG: 5, sleepByte: nil)
        }
        let rr = ts.map { RRInterval(timestampMs: $0, milliseconds: 1000) }
        let night = SleepDetector.detect(heartRate: [], rr: rr, motion: motion)
        #expect(night.onsetMs == Self.base)
    }

    @Test func aHighHeartRateIsNotSleep() {
        let night = Self.night((0..<12).map { ($0, 5, Optional(110)) })
        #expect(night.onsetMs == nil)
        #expect(night.epochs.allSatisfy { $0.kind == .awake })
    }

    @Test func gravityStillnessCountsWhenDynamicIsMissing() {
        let ts = (0..<12).map { Self.base + Int64($0) * 60_000 }
        let motion = ts.map {
            MotionSample(timestampMs: $0, xMilliG: 10, yMilliG: 20, zMilliG: 1000, dynamicMilliG: nil, sleepByte: nil)
        }
        let hr = ts.map { HeartRateSample(timestampMs: $0, bpm: 50) }
        let night = SleepDetector.detect(heartRate: hr, rr: [], motion: motion)
        // The first minute has no previous vector, so stillness starts at minute 1.
        #expect(night.onsetMs == Self.base + 60_000)
    }

    @Test func smartWakeHoldsOutsideTheWindowAndWhileStillAsleep() {
        let deadline = Self.base + 60 * 60_000
        let asleep = (0..<40).map { SleepEpoch(startMs: Self.base + Int64($0) * 60_000, kind: .asleep) }
        #expect(SleepDetector.smartWake(epochs: asleep, nowMs: deadline - 31 * 60_000, deadlineMs: deadline) == .hold)
        #expect(SleepDetector.smartWake(epochs: asleep, nowMs: deadline - 10 * 60_000, deadlineMs: deadline) == .hold)
        #expect(SleepDetector.smartWake(epochs: asleep, nowMs: deadline, deadlineMs: deadline) == .hold)
    }

    @Test func smartWakeBuzzesWhenAStirFollowsSleepInsideTheWindow() {
        let deadline = Self.base + 60 * 60_000
        var epochs = (0..<40).map { SleepEpoch(startMs: Self.base + Int64($0) * 60_000, kind: .asleep) }
        epochs.append(SleepEpoch(startMs: Self.base + 40 * 60_000, kind: .restless))
        let now = Self.base + 40 * 60_000 + 30_000
        #expect(now >= deadline - SleepDetector.windowMs)
        #expect(SleepDetector.smartWake(epochs: epochs, nowMs: now, deadlineMs: deadline) == .buzzEarly)
        epochs[epochs.count - 1] = SleepEpoch(startMs: Self.base + 40 * 60_000, kind: .awake)
        #expect(SleepDetector.smartWake(epochs: epochs, nowMs: now, deadlineMs: deadline) == .buzzEarly)
    }

    @Test func smartWakeDoesNotBuzzSomeoneWhoWasNeverAsleep() {
        let deadline = Self.base + 60 * 60_000
        let awake = (30..<50).map { SleepEpoch(startMs: Self.base + Int64($0) * 60_000, kind: .awake) }
        #expect(SleepDetector.smartWake(epochs: awake, nowMs: Self.base + 45 * 60_000, deadlineMs: deadline) == .hold)
    }
}
