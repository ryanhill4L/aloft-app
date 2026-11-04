import AloftStrap
import SwiftUI

/// Set the wake time. The strap is armed at that time. The half hour before
/// can buzz early only while the phone is connected.
struct WakeView: View {
    @Environment(AppModel.self) private var model
    @State private var time = Date()

    private var calendar: Calendar { .current }
    private var deadline: Date {
        WakeSchedule.nextDeadline(
            hour: calendar.component(.hour, from: time),
            minute: calendar.component(.minute, from: time),
            now: .now,
            calendar: calendar
        )
    }

    var body: some View {
        StepScreen(
            stamp: "Wake",
            title: deadline.formatted(date: .omitted, time: .shortened),
            subtitle: "The strap buzzes at this time even if the phone is away. From \(WakeSchedule.windowStart(deadline).formatted(date: .omitted, time: .shortened)), if the phone is connected and you stir, the strap can buzz earlier and Aloft then clears that alarm. The phone does not sound.",
            onBack: { model.route = .home },
            lead: { EmptyView() },
            work: {
                VStack(alignment: .leading, spacing: Space.s4) {
                    DatePicker("Wake time", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxHeight: 180)
                        .accessibilityLabel("Wake time")
                    Text(readback)
                        .textStyle(.small)
                        .foregroundStyle(Palette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            },
            action: PrimaryAction(title: "Arm the strap", enabled: true) {
                model.strap.armWake(deadline)
            }
        )
        .onAppear {
            if let saved = model.strap.wakeDeadline { time = saved }
        }
    }

    private var readback: String {
        let strap = model.strap
        guard let saved = strap.wakeDeadline else {
            return "Nothing is armed. Arming writes the time onto the strap and reads it back."
        }
        let when = saved.formatted(date: .omitted, time: .shortened)
        guard let body = strap.alarmReadback?.body else {
            return "Saved for \(when). The strap has not confirmed it yet. A result code only means the bytes were accepted."
        }
        if WakeSchedule.confirms(body, deadline: saved) {
            return "The strap read back \(when). That is the guaranteed buzz."
        }
        return "The strap read back a different time than \(when)."
    }
}
