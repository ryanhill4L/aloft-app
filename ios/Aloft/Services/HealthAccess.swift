import Foundation
import HealthKit

/// Read-only Apple Health access. Everything read stays on the phone.
@MainActor
final class HealthAccess {
    struct Choices: Equatable {
        var sleep = true
        var heartRate = true
        var hrv = true
        var workouts = false
    }

    /// The night and heart readings Home shows. A nil field is shown as missing.
    struct Snapshot: Equatable {
        var sleep: TimeInterval?
        var hrvMs: Double?
        var restingBPM: Double?
    }

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess(_ choices: Choices) async throws {
        guard isAvailable else { return }
        var types: Set<HKObjectType> = []
        if choices.sleep { types.insert(HKCategoryType(.sleepAnalysis)) }
        if choices.heartRate {
            types.insert(HKQuantityType(.heartRate))
            types.insert(HKQuantityType(.restingHeartRate))
        }
        if choices.hrv { types.insert(HKQuantityType(.heartRateVariabilitySDNN)) }
        if choices.workouts { types.insert(HKWorkoutType.workoutType()) }
        guard !types.isEmpty else { return }
        try await store.requestAuthorization(toShare: [], read: types)
    }

    func snapshot(now: Date = .now) async -> Snapshot {
        guard isAvailable else { return Snapshot() }
        async let sleep = lastNightSleep(now: now)
        async let hrv = latest(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), now: now)
        async let resting = latest(.restingHeartRate, unit: .count().unitDivided(by: .minute()), now: now)
        return await Snapshot(sleep: sleep, hrvMs: hrv, restingBPM: resting)
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit, now: Date) async -> Double? {
        let predicate = HKSamplePredicate.quantitySample(
            type: HKQuantityType(id),
            predicate: HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-36 * 3600), end: now)
        )
        let query = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 1)
        return try? await query.result(for: store).first?.quantity.doubleValue(for: unit)
    }

    /// Asleep time between 18:00 yesterday and noon today.
    private func lastNightSleep(now: Date) async -> TimeInterval? {
        let cal = Calendar.current
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        let start = noon.addingTimeInterval(-18 * 3600)
        let predicate = HKSamplePredicate.categorySample(
            type: HKCategoryType(.sleepAnalysis),
            predicate: HKQuery.predicateForSamples(withStart: start, end: noon)
        )
        let query = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [])
        guard let samples = try? await query.result(for: store) else { return nil }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        let total = samples.filter { asleep.contains($0.value) }.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        return total > 0 ? total : nil
    }
}
