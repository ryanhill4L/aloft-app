import AloftStrap
import SwiftUI

/// Last night, after the sync. Missing numbers stay missing. Stages appear
/// only when the detector produced them.
struct RecapView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recap = model.recap
        StepScreen(
            stamp: "Last night",
            title: recap.map { MorningRecap.hoursMinutes($0.asleepSeconds) } ?? "No night yet",
            subtitle: recap.map { "asleep of \(MorningRecap.hoursMinutes($0.goalSeconds))" } ?? "A sync that finds sleep onset will land here.",
            onBack: { model.route = .home },
            lead: { EmptyView() },
            work: {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let recap {
                        line("Efficiency", recap.efficiency.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                        line("Onset", clock(recap.onsetMs))
                        line("Wake", clock(recap.wakeMs))
                        line("Resting", recap.restingBPM.map { "\($0)" } ?? "—")
                        line("Average", recap.averageBPM.map { "\($0)" } ?? "—")
                        Text(recap.hasStages ? "Stages are an on-device estimate, not WHOOP’s." : recap.stageNote)
                            .textStyle(.small)
                            .foregroundStyle(Palette.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            },
            action: PrimaryAction(title: "Done") { model.route = .home }
        )
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Stamp(label)
            Spacer()
            Text(value).textStyle(.readout).foregroundStyle(Palette.ink)
        }
        .frame(minHeight: 36)
    }

    private func clock(_ ms: Int64?) -> String {
        guard let ms else { return "—" }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000).formatted(date: .omitted, time: .shortened)
    }
}
