import AloftStrap
import SwiftUI

// MARK: Crew

/// The Crew: weather words, never numbers, and Lifts.
struct CrewTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split
    @State private var liftTarget: Aloft_V1_CrewMember?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Stamp("0.2 Crew")
                    Spacer()
                    if let crew = model.crew { Stamp("\(crew.members.count) under your sky") }
                }
                if let crew = model.crew {
                    VStack(spacing: 0) {
                        ForEach(others(crew), id: \.userID) { member in
                            HStack(spacing: Space.s3) {
                                Avatar(name: member.firstName)
                                Text(member.firstName).textStyle(.body).foregroundStyle(Palette.ink)
                                Spacer()
                                let weather = Weather(member.weather)
                                Text(weather?.rawValue ?? "Not yet").textStyle(.small).foregroundStyle(color(for: weather))
                                Button("Lift") { liftTarget = member }
                                    .buttonStyle(.chip(.lampOutline))
                                    .accessibilityLabel("Send \(member.firstName) a Lift")
                            }
                            .frame(minHeight: 52)
                            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
                        }
                    }
                    if others(crew).isEmpty {
                        Text("Nobody else here yet. Send your code to the people you rise with.")
                            .textStyle(.small).foregroundStyle(Palette.inkMuted)
                    }
                    ShareLink(item: "Rise with me on Aloft. Our Crew code is \(crew.code).") {
                        Text("Invite with code \(crew.code)")
                    }
                    .buttonStyle(.ghost)
                } else {
                    Text("You’re not in a Crew yet.").textStyle(.title).foregroundStyle(Palette.ink)
                    Button("Start a Crew") { Task { await model.createCrew() } }.buttonStyle(.lamp)
                }
                ForEach(model.lifts, id: \.id) { lift in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lift.message).textStyle(.voiceSmall).foregroundStyle(Palette.ink)
                        Stamp("\(lift.fromFirstName) · \(SkyTab.time(lift.sentAtUnix))", color: Palette.lamp)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.lampTint, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }
            }
            .padding(.horizontal, split == .single ? Space.s5 : 40)
            .padding(.vertical, Space.s5)
        }
        .sheet(item: $liftTarget) { member in
            LiftComposer(member: member).presentationDetents([.medium])
        }
    }

    private func others(_ crew: Aloft_V1_Crew) -> [Aloft_V1_CrewMember] {
        crew.members.filter { $0.userID != model.profile.userID }
    }
}

extension Aloft_V1_CrewMember: Identifiable {
    public var id: String { userID }
}

struct LiftComposer: View {
    let member: Aloft_V1_CrewMember
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Stamp("Lift for \(member.firstName)")
            TextField("", text: $text, prompt: Text("A few words…").foregroundStyle(Palette.inkFaint), axis: .vertical)
                .textStyle(.voice)
                .foregroundStyle(Palette.ink)
                .lineLimit(3...6)
                .padding(Space.s4)
                .background(Palette.lampTint, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Stamp("\(text.count) / 280")
            if let error = model.error { Text(error).textStyle(.small).foregroundStyle(Palette.ember) }
            Spacer()
            Button("Send a Lift") {
                Task { if await model.sendLift(to: member, message: text) { dismiss() } }
            }
            .buttonStyle(.lamp)
            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || text.count > 280)
        }
        .padding(Space.s5)
        .presentationBackground(Palette.ground)
    }
}

// MARK: Log

/// The milestone 1 debug view: link, last sync, last error, store path and
/// row counts, recent log lines, and the full trace file to share. Nothing is
/// uploaded.
struct LogTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split
    @State private var counts: StoreCounts?

    var body: some View {
        let strap = model.strap
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Stamp("0.3 Log · strap")
                Text(strap.statusLine)
                    .textStyle(.small)
                    .foregroundStyle(Palette.inkMuted)
                Card {
                    VStack(spacing: 0) {
                        row("Link", strap.state.name)
                        row("Live heart", strap.liveBPM.map { "\($0) BPM" } ?? "—")
                        row("Last sync", strap.lastSync?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                        row("Last error", strap.lastError ?? "None")
                        row("HR rows", counts.map { "\($0.heartRate)" } ?? "—")
                        row("R-R rows", counts.map { "\($0.rr)" } ?? "—")
                        row("Motion rows", counts.map { "\($0.motion)" } ?? "—")
                        row("Store", strap.store == nil ? "Unavailable" : "On this phone", last: true)
                    }
                }
                alarmSection(strap)
                HStack(spacing: Space.s3) {
                    Button("Find") { strap.find() }.buttonStyle(.ghost)
                    Button("Retry") { strap.retry() }.buttonStyle(.ghost)
                }
                HStack(spacing: Space.s3) {
                    Button("Disconnect") { strap.disconnect() }.buttonStyle(.ghost)
                    Button("Forget") { strap.forget() }.buttonStyle(.ghost)
                }
                HStack(spacing: Space.s3) {
                    if strap.trace.files.isEmpty {
                        ShareLink(item: report(strap)) { Text("Share log") }.buttonStyle(.ghost)
                    } else {
                        ShareLink(items: strap.trace.files, message: Text(report(strap))) { Text("Share log") }.buttonStyle(.ghost)
                    }
                }
                Stamp("Recent")
                VStack(alignment: .leading, spacing: 2) {
                    if strap.log.isEmpty {
                        Text("No strap activity yet. The Simulator has no Bluetooth path to a strap; pair on a phone.")
                            .textStyle(.small).foregroundStyle(Palette.inkMuted)
                    }
                    ForEach(Array(strap.log.suffix(80).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.custom("IBMPlexMono-Regular", size: 12)).foregroundStyle(Palette.inkMuted)
                    }
                }
                .textSelection(.enabled)
            }
            .padding(.horizontal, split == .single ? Space.s5 : 40)
            .padding(.vertical, Space.s5)
        }
        .task(id: strap.lastSync) {
            counts = try? await strap.store?.counts()
            await strap.reloadEvents()
        }
    }

    /// Buzz, arm, read, and disarm. Frames go out through `StrapLink`. The
    /// Simulator has no CoreBluetooth path, so these buttons need a phone.
    private func alarmSection(_ strap: StrapLink) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Stamp("Strap alarm")
            Text("A result code means the strap accepted the bytes, not that it buzzed. These buttons need a phone; the Simulator cannot reach a strap.")
                .textStyle(.small)
                .foregroundStyle(Palette.inkMuted)
            Group {
                HStack(spacing: Space.s3) {
                    Button("Buzz") { strap.buzz() }.buttonStyle(.ghost)
                    Button("Arm in +2 min") { strap.armInTwoMinutes() }.buttonStyle(.ghost)
                }
                HStack(spacing: Space.s3) {
                    Button("Read alarm") { strap.readAlarm() }.buttonStyle(.ghost)
                    Button("Disarm") { strap.disarmAll() }.buttonStyle(.ghost)
                }
            }
            .disabled(!strap.canCommand)
            .opacity(strap.canCommand ? 1 : 0.4)
            if let clock = strap.clockNote {
                mono(clock)
            }
            if let read = strap.alarmReadback {
                mono(alarmText(read))
            } else {
                Text("No alarm read yet.").textStyle(.small).foregroundStyle(Palette.inkMuted)
            }
            Stamp("Command results")
            if strap.commandResults.isEmpty {
                Text("No command result yet.").textStyle(.small).foregroundStyle(Palette.inkMuted)
            }
            ForEach(Array(strap.commandResults.suffix(12).enumerated()), id: \.offset) { _, response in
                mono("\(strap.commandTitle(response.command)) · \(response.result) \(response.resultName)")
            }
            Stamp("Strap events")
            if strap.strapEvents.isEmpty {
                Text("No strap events yet. Alarm set, alarm fired, haptics, and wrist on or off show up here.")
                    .textStyle(.small)
                    .foregroundStyle(Palette.inkMuted)
            }
            ForEach(Array(strap.strapEvents.suffix(12).enumerated()), id: \.offset) { _, event in
                mono("\(event.label) · \(event.id) · \(event.unixSeconds)")
            }
        }
    }

    private func mono(_ line: String) -> some View {
        Text(line)
            .font(.custom("IBMPlexMono-Regular", size: 12))
            .foregroundStyle(Palette.inkMuted)
            .textSelection(.enabled)
    }

    /// 5/MG GET body is the 21-byte record (`04`, slot, epoch). WHOOP 4 starts
    /// with `01` and the epoch.
    private func alarmText(_ response: CommandResponse) -> String {
        let head = "get alarm · cmd \(response.command) origin \(response.originSequence) result \(response.result) \(response.resultName)"
        let body = response.body
        if body.count >= 7, body[0] == 0x04 {
            let epoch = u32le(body, 2)
            return "\(head)\nslot \(body[1]) epoch \(epoch) \(clock(epoch))"
        }
        if body.count >= 5, body[0] == 0x01 {
            let epoch = u32le(body, 1)
            return "\(head)\nepoch \(epoch) \(clock(epoch))"
        }
        guard !body.isEmpty else { return head }
        let hex = body.map { String(format: "%02x", $0) }.joined()
        return "\(head)\nbody \(hex)"
    }

    private func u32le(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | (UInt32(bytes[at + 1]) << 8) | (UInt32(bytes[at + 2]) << 16) | (UInt32(bytes[at + 3]) << 24)
    }

    private func clock(_ epoch: UInt32) -> String {
        Date(timeIntervalSince1970: TimeInterval(epoch)).formatted(date: .abbreviated, time: .standard)
    }

    private func row(_ label: String, _ value: String, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Stamp(label)
            Spacer(minLength: Space.s4)
            Text(value).textStyle(.readout).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Palette.line).frame(height: 1) } }
    }

    private func report(_ strap: StrapLink) -> String {
        var lines = ["Aloft strap log", "state: \(strap.state.name)", strap.statusLine]
        if let counts { lines.append("hr: \(counts.heartRate), rr: \(counts.rr), motion: \(counts.motion)") }
        if let error = strap.lastError { lines.append("last error: \(error)") }
        if let clock = strap.clockNote { lines.append(clock) }
        if let read = strap.alarmReadback { lines.append(alarmText(read).replacingOccurrences(of: "\n", with: " ")) }
        lines += strap.commandResults.suffix(8).map {
            "\($0.command) \(strap.commandTitle($0.command)): \($0.result) \($0.resultName)"
        }
        lines += strap.strapEvents.suffix(8).map { "\($0.label) \($0.id) \($0.unixSeconds)" }
        return (lines + strap.log.suffix(80)).joined(separator: "\n")
    }
}

/// The Log tab before an account exists, opened from Landing.
struct BandCheckView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back") { model.route = .landing }.buttonStyle(.link)
                Spacer()
            }
            .padding(.horizontal, split == .single ? Space.s5 : 40)
            LogTab()
        }
        .background(Palette.ground.ignoresSafeArea())
    }
}

// MARK: You

struct YouTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split

    var body: some View {
        let p = model.profile
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                Stamp("0.4 You")
                HStack(spacing: Space.s3) {
                    Avatar(name: p.firstName, size: 48)
                    Text(p.firstName.isEmpty ? "You" : p.firstName).textStyle(.title).foregroundStyle(Palette.ink)
                }
                VStack(spacing: Space.s2) {
                    ValueRow(label: "Born", value: p.birthYear > 0 ? "\(p.birthYear)" : "—") {}
                    ValueRow(label: "Height", value: p.heightCm > 0 ? BasicsStep.height(Double(p.heightCm), metric: false) : "—") {}
                    ValueRow(label: "Weight", value: p.weightKg > 0 ? BasicsStep.weight(Double(p.weightKg), metric: false) : "—") {}
                    ValueRow(label: "Nights", value: String(format: "%02d:%02d – %02d:%02d", p.bedtimeMinutes / 60, p.bedtimeMinutes % 60, p.wakeMinutes / 60, p.wakeMinutes % 60)) {}
                    ValueRow(label: "Wake", value: model.strap.wakeDeadline?.formatted(date: .omitted, time: .shortened) ?? "Set") {
                        model.route = .wake
                    }
                }
                Text("Scores are on-device estimates, not WHOOP’s models and not medical advice. Aloft is not affiliated with WHOOP.")
                    .textStyle(.small).foregroundStyle(Palette.inkMuted)
                Button("Sign out") { Task { await model.signOut() } }.buttonStyle(.ghost)
            }
            .padding(.horizontal, split == .single ? Space.s5 : 40)
            .padding(.vertical, Space.s5)
        }
    }
}
