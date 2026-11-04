import Foundation
import Testing
@testable import AloftStrap

@Suite struct MorningRecapTests {
    @Test func aFinishedNightFillsTheCardAndTheNotification() {
        let onset: Int64 = 1_700_000_000_000
        let wake = onset + 8 * 60 * 60 * 1000
        let night = SleepNight(
            inBedStartMs: onset - 30 * 60 * 1000,
            onsetMs: onset,
            wakeMs: wake,
            asleepMs: (7 * 60 + 12) * 60 * 1000,
            inBedMs: (7 * 60 + 42) * 60 * 1000,
            efficiency: 0.864,
            epochs: [],
            stages: nil,
            note: SleepNight.stageNote
        )
        let hr = [
            HeartRateSample(timestampMs: onset + 1_000, bpm: 52),
            HeartRateSample(timestampMs: onset + 2_000, bpm: 48),
            HeartRateSample(timestampMs: wake, bpm: 90),
        ]
        let recap = MorningRecap.from(night: night, heartRate: hr)
        #expect(recap?.asleepSeconds == (7 * 60 + 12) * 60)
        #expect(recap?.goalSeconds == 8 * 60 * 60)
        #expect(recap?.restingBPM == 48)
        #expect(recap?.averageBPM == 50)
        #expect(recap?.hasStages == false)
        #expect(recap?.notificationTitle == "Last night")
        #expect(recap?.notificationBody == "7h 12m asleep of 8h. Efficiency 86%")
        #expect(recap?.shouldNotify(alreadyNotifiedOnsetMs: nil) == true)
        #expect(recap?.shouldNotify(alreadyNotifiedOnsetMs: onset) == false)
    }

    @Test func anOpenNightDoesNotNotify() {
        let night = SleepNight(
            inBedStartMs: 1_000, onsetMs: 1_000, wakeMs: nil, asleepMs: 60_000,
            inBedMs: nil, efficiency: nil, epochs: [], stages: nil, note: SleepNight.stageNote
        )
        let recap = MorningRecap.from(night: night, heartRate: [])
        #expect(recap?.restingBPM == nil)
        #expect(recap?.shouldNotify(alreadyNotifiedOnsetMs: nil) == false)
        #expect(recap?.notificationBody == "0h 1m asleep of 8h")
    }

    @Test func noOnsetMeansNoRecap() {
        let night = SleepNight(
            inBedStartMs: nil, onsetMs: nil, wakeMs: nil, asleepMs: 0,
            inBedMs: nil, efficiency: nil, epochs: [], stages: nil, note: "No heart rate or motion in this window."
        )
        #expect(MorningRecap.from(night: night, heartRate: []) == nil)
    }
}
