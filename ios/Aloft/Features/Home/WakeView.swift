import AloftStrap
import SwiftUI

/// A week of wake times. The strap only holds the next one. The half hour
/// before that buzz can still fire early while the phone is connected.
struct WakeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split
    @State private var week = WeeklyWake.off
    @State private var shared = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? .now

    private var calendar: Calendar { .current }
    private var next: Date? { WakeSchedule.nextDeadline(week, now: .now, calendar: calendar) }

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            switch split {
            case .sideBySide: sideBySide
            case .stacked, .single: scrolling
            }
        }
        .onAppear { week = model.strap.schedule }
    }

    private var scrolling: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                heading
                editor
            }
            .padding(.horizontal, split == .single ? Space.s5 : Space.s6)
            .padding(.vertical, Space.s4)
        }
    }

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: 64) {
            heading.frame(maxWidth: .infinity, alignment: .leading)
            ScrollView { editor }.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, Space.s5)
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Button("Back") { model.route = .home }.buttonStyle(.link)
                Spacer()
            }
            Stamp("Wake")
            Text(next?.formatted(.dateTime.weekday(.abbreviated).hour().minute()) ?? "Off")
                .textStyle(split == .single ? .title : .display)
                .foregroundStyle(Palette.ink)
            Text(subtitle)
                .textStyle(.small)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        guard let next else {
            return "Every day is off, so the strap alarm is cleared. The phone does not sound."
        }
        let window = WakeSchedule.windowStart(next).formatted(date: .omitted, time: .shortened)
        let when = next.formatted(date: .omitted, time: .shortened)
        return "The strap holds the next buzz, \(when), even if the phone is away. From \(window), if the phone is connected and you stir, it can buzz earlier and Aloft then arms the morning after. The phone does not sound."
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            DatePicker("Time", selection: $shared, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
            Button("Use this time every day") { applySharedTime() }
                .buttonStyle(.ghost)
            VStack(spacing: Space.s2) {
                ForEach(displayOrder, id: \.self) { index in
                    dayRow(index)
                }
            }
            Text(readback)
                .textStyle(.small)
                .foregroundStyle(Palette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayOrder: [Int] { [1, 2, 3, 4, 5, 6, 0] }

    private func dayRow(_ index: Int) -> some View {
        let name = calendar.shortWeekdaySymbols[index]
        return HStack(spacing: Space.s3) {
            Toggle(name, isOn: Binding(
                get: { week.days[index].enabled },
                set: { on in
                    week.days[index].enabled = on
                    save()
                }
            ))
            .tint(Palette.sky)
            DatePicker(
                name,
                selection: Binding(
                    get: { date(minutes: week.days[index].minutes) },
                    set: { new in
                        week.days[index].minutes = minutes(from: new)
                        save()
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
            .frame(width: 110)
        }
        .frame(minHeight: 44)
    }

    private var readback: String {
        let strap = model.strap
        guard let saved = strap.wakeDeadline else {
            return "Nothing is armed."
        }
        let when = saved.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        guard let body = strap.alarmReadback?.body else {
            return "Next buzz \(when). The strap has not confirmed it yet."
        }
        if WakeSchedule.confirms(body, deadline: saved) {
            return "The strap read back \(when). That is the guaranteed buzz."
        }
        return "The strap read back a different time than \(when)."
    }

    private func applySharedTime() {
        let minutes = minutes(from: shared)
        week = WeeklyWake(days: week.days.map { _ in .init(enabled: true, minutes: minutes) })
        save()
    }

    private func save() {
        model.strap.updateSchedule(week)
    }

    private func date(minutes: Int) -> Date {
        calendar.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? shared
    }

    private func minutes(from date: Date) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
