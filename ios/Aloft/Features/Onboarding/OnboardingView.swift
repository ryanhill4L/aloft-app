import SwiftUI

/// Onboarding 01–06. Each step is a StepScreen with the step dots in the top
/// bar; the draft is saved to the profile API once, on Finish.
struct OnboardingView: View {
    let step: OnboardingStep

    var body: some View {
        switch step {
        case .name: NameStep()
        case .basics: BasicsStep()
        case .band: BandStep()
        case .health: HealthStep()
        case .crew: CrewStep()
        case .nights: NightsStep()
        }
    }
}

/// Shared wrapper: stamp numbering, Back, and the dots.
struct OnboardingScreen<Lead: View, Work: View>: View {
    let step: OnboardingStep
    let stamp: String
    let title: String
    var subtitle: String?
    @ViewBuilder var lead: Lead
    @ViewBuilder var work: Work
    let action: PrimaryAction

    @Environment(AppModel.self) private var model

    var body: some View {
        StepScreen(
            stamp: stamp,
            title: title,
            subtitle: subtitle,
            onBack: { model.back(from: step) },
            trailing: { StepDots(current: step.rawValue) },
            lead: { lead },
            work: { work },
            action: action
        )
    }
}

// MARK: 01 Name

struct NameStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        let name = model.draft.firstName.trimmingCharacters(in: .whitespaces)
        OnboardingScreen(
            step: .name,
            stamp: "0.3 Your name",
            title: "What should your Crew call you?",
            subtitle: "Your first name is enough. It signs every Lift you send.",
            lead: { EmptyView() },
            work: {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Stamp("First name")
                    TextField("", text: $model.draft.firstName, prompt: Text("Ryan").foregroundStyle(Palette.inkFaint))
                        .font(.custom("HostGrotesk-Regular", size: 20))
                        .foregroundStyle(Palette.ink)
                        .textContentType(.givenName)
                        .submitLabel(.continue)
                        .focused($focused)
                        .padding(.horizontal, Space.s4)
                        .frame(height: split == .single ? 56 : 60)
                        .background(Palette.well, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: 1))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.md + 4, style: .continuous)
                                .strokeBorder(Palette.sky, lineWidth: 2).padding(-4)
                                .opacity(focused ? 1 : 0)
                        }
                        .accessibilityLabel("First name")
                        .onSubmit { if !name.isEmpty { model.advance(from: .name) } }
                }
                Spacer(minLength: Space.s4)
                Card(padding: split == .single ? 16 : Space.s5) {
                    HStack(spacing: Space.s3) {
                        Avatar(name: name.isEmpty ? "·" : name, size: split == .single ? 40 : 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Stamp("How your Crew sees you")
                            (Text(name.isEmpty ? "Your name" : name).foregroundStyle(name.isEmpty ? Palette.inkFaint : Palette.ink)
                                + Text(" · ").foregroundStyle(Palette.inkMuted)
                                + Text("Fair").foregroundStyle(Palette.fair))
                                .textStyle(split == .single ? .body : .heading)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            },
            action: PrimaryAction(title: "Continue", enabled: !name.isEmpty) { model.advance(from: .name) }
        )
        .onAppear { focused = true }
    }
}

// MARK: 02 Basics

struct BasicsStep: View {
    enum Field { case born, height, weight }

    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split
    @State private var field: Field = .height
    @AppStorage("aloft.metric") private var metric = false

    var body: some View {
        OnboardingScreen(
            step: .basics,
            stamp: "0.4 Basics",
            title: "A few basics.",
            subtitle: "These help Aloft set your Ceiling. Only you see them.",
            lead: {
                if split != .single {
                    Spacer(minLength: 0)
                    rows
                }
            },
            work: {
                if split == .single {
                    rows
                } else {
                    units
                }
                Spacer(minLength: 0)
                if split != .single { Stamp(label).frame(maxWidth: .infinity) }
                Text(readout)
                    .textStyle(split == .single ? .readoutLG : .readoutXL)
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .contentTransition(.numericText())
                    .accessibilityHidden(true)
                ruler
            },
            action: PrimaryAction(title: "Continue") { model.advance(from: .basics) }
        )
    }

    private var rows: some View {
        VStack(spacing: Space.s2) {
            ValueRow(label: "Born", value: "\(model.draft.birthYear)", selected: field == .born) { field = .born }
            ValueRow(label: "Height", value: Self.height(model.draft.heightCM, metric: metric), selected: field == .height) { field = .height }
            ValueRow(label: "Weight", value: Self.weight(model.draft.weightKG, metric: metric), selected: field == .weight) { field = .weight }
        }
    }

    private var units: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { isMetric in
                Button(isMetric ? "Metric" : "Imperial") { metric = isMetric }
                    .font(.custom("HostGrotesk-Medium", size: 14))
                    .foregroundStyle(metric == isMetric ? Palette.ink : Palette.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(metric == isMetric ? Palette.raised : .clear, in: Capsule())
                    .accessibilityAddTraits(metric == isMetric ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Palette.well, in: Capsule())
    }

    private var label: String {
        switch field {
        case .born: "Born"
        case .height: "Height"
        case .weight: "Weight"
        }
    }

    private var readout: String {
        switch field {
        case .born: "\(model.draft.birthYear)"
        case .height: Self.height(model.draft.heightCM, metric: metric)
        case .weight: Self.weight(model.draft.weightKG, metric: metric)
        }
    }

    @ViewBuilder
    private var ruler: some View {
        @Bindable var model = model
        let height: CGFloat = split == .single ? 40 : 44
        switch field {
        case .born:
            Ruler(value: Binding(get: { Double(model.draft.birthYear) }, set: { model.draft.birthYear = Int($0) }),
                  range: 1930...Double(Calendar.current.component(.year, from: .now) - 13), step: 1, height: height)
                .accessibilityLabel("Birth year").accessibilityValue(readout)
        case .height:
            Ruler(value: $model.draft.heightCM, range: 120...230, step: metric ? 1 : 2.54, height: height)
                .accessibilityLabel("Height").accessibilityValue(readout)
        case .weight:
            Ruler(value: $model.draft.weightKG, range: 35...200, step: metric ? 1 : 0.4536, height: height)
                .accessibilityLabel("Weight").accessibilityValue(readout)
        }
    }

    static func height(_ cm: Double, metric: Bool) -> String {
        if metric { return "\(Int(cm.rounded())) CM" }
        let inches = Int((cm / 2.54).rounded())
        return "\(inches / 12)′\(inches % 12)″"
    }

    static func weight(_ kg: Double, metric: Bool) -> String {
        metric ? "\(Int(kg.rounded())) KG" : "\(Int((kg / 0.4536).rounded())) LB"
    }
}

// MARK: 03 Band

struct BandStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let strap = model.strap
        OnboardingScreen(
            step: .band,
            stamp: "0.5 Your band",
            title: "Pair your band.",
            subtitle: "Hold it near your phone. Aloft finds it on its own.",
            lead: { EmptyView() },
            work: {
                Card {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        Stamp(strap.found.isEmpty ? "Looking nearby" : "Found nearby")
                        if strap.found.isEmpty {
                            HStack(spacing: Space.s4) {
                                bandGlyph
                                Text(statusLine(strap.state)).textStyle(.small).foregroundStyle(Palette.inkMuted)
                            }
                        }
                        ForEach(strap.found) { found in
                            Button { strap.connect(found) } label: {
                                HStack(spacing: Space.s4) {
                                    bandGlyph
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(found.name).textStyle(.body).foregroundStyle(Palette.ink)
                                        Stamp("\(found.family == .whoop4 ? "WHOOP 4.0" : "WHOOP 5.0 / MG") · \(found.rssi) dBm")
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("The strap pairs with one app at a time. If nothing shows up, unpair it in the official WHOOP app and close that app, then come back.")
                    .textStyle(.small).foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Skip for now") { model.advance(from: .band) }
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity)
            },
            action: PrimaryAction(title: pairTitle(strap), enabled: !strap.found.isEmpty || strap.state == .live) {
                if strap.state == .live || strap.state == .syncing {
                    model.advance(from: .band)
                } else if let first = strap.found.first {
                    strap.connect(first)
                }
            }
        )
        .onAppear { strap.startScan() }
    }

    private func pairTitle(_ strap: StrapLink) -> String {
        switch strap.state {
        case .connecting, .bonding: "Pairing…"
        case .syncing, .live: "Continue"
        default: "Pair band"
        }
    }

    private func statusLine(_ state: StrapLink.State) -> String {
        switch state {
        case .off: "Bluetooth is off. Turn it on in Control Center."
        case .unauthorized: "Aloft needs Bluetooth. Allow it in Settings › Aloft."
        case let .failed(message): message
        default: "Searching for a WHOOP 4.0 or 5.0 strap…"
        }
    }

    private var bandGlyph: some View {
        Canvas { ctx, _ in
            ctx.stroke(Path(roundedRect: CGRect(x: 12, y: 4, width: 16, height: 32), cornerRadius: 6), with: .color(Palette.inkMuted), lineWidth: 1.2)
            ctx.stroke(Path(roundedRect: CGRect(x: 14, y: 13, width: 12, height: 14), cornerRadius: 3), with: .color(Palette.inkMuted), lineWidth: 1.2)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }
}

// MARK: 04 Health

struct HealthStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        OnboardingScreen(
            step: .health,
            stamp: "0.6 Health",
            title: "Let Aloft read your nights.",
            subtitle: "Aloft reads from Apple Health to understand your sleep and your heart.",
            lead: { EmptyView() },
            work: {
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        SkyToggle(title: "Sleep", isOn: $model.draft.health.sleep)
                        Divider().overlay(Palette.line)
                        SkyToggle(title: "Heart rate", isOn: $model.draft.health.heartRate)
                        Divider().overlay(Palette.line)
                        SkyToggle(title: "Heart rate variability", isOn: $model.draft.health.hrv)
                        Divider().overlay(Palette.line)
                        SkyToggle(title: "Workouts", isOn: $model.draft.health.workouts)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                }
                Text("Your numbers stay on this phone. Your Crew sees weather, never figures.")
                    .textStyle(.small).foregroundStyle(Palette.inkMuted)
                Spacer(minLength: 0)
                Button("Not now") { model.advance(from: .health) }
                    .buttonStyle(.link)
                    .frame(maxWidth: .infinity)
            },
            action: PrimaryAction(title: "Allow in Health") { Task { await model.requestHealth() } }
        )
    }
}

// MARK: 05 Crew

struct CrewStep: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split
    @State private var code = ""
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingScreen(
            step: .crew,
            stamp: "0.7 Crew",
            title: "Who do you rise with?",
            subtitle: "A Crew is up to 12 people under one sky. They see your weather, never your numbers.",
            lead: {
                if split != .single {
                    ZStack(alignment: .top) {
                        Window(kind: .crew, fades: false)
                        HStack {
                            Stamp("Crew sky", color: Palette.onWindow)
                            Spacer()
                            Stamp(String(format: "%02d / 12", max(model.crew?.members.count ?? 1, 1)), color: Palette.onWindow)
                        }
                        .padding(20)
                    }
                    .frame(height: 196)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                }
            },
            work: {
                if let crew = model.crew {
                    yourCrew(crew)
                } else {
                    join
                }
                if let error = model.error {
                    Text(error).textStyle(.small).foregroundStyle(Palette.ember)
                }
                Spacer(minLength: 0)
            },
            action: PrimaryAction(title: "Continue") { model.advance(from: .crew) }
        )
        .onAppear { model.error = nil }
    }

    private var join: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            FieldBox(focused: focused, height: split == .single ? 56 : 60) {
                Stamp("Crew code")
                TextField("", text: $code, prompt: Text("— — — — — —").foregroundStyle(Palette.inkFaint))
                    .font(.custom("IBMPlexMono-Light", size: 18))
                    .foregroundStyle(Palette.ink)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .accessibilityLabel("Crew code")
                    .onChange(of: code) { _, new in code = String(new.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)) }
                Button("Join") { Task { await model.joinCrew(code: code) } }
                    .buttonStyle(.chip(.lampOutline))
                    .disabled(code.count != 6 || model.busy)
                    .opacity(code.count == 6 ? 1 : 0.4)
            }
            HStack(spacing: Space.s3) {
                Rectangle().fill(Palette.line).frame(height: 1)
                Stamp("Or")
                Rectangle().fill(Palette.line).frame(height: 1)
            }
            .padding(.vertical, Space.s2)
            Button("Start a Crew") { Task { await model.createCrew() } }
                .buttonStyle(.chip(.lamp))
            Text("You’ll get a code to send the people you rise with.")
                .textStyle(.small).foregroundStyle(Palette.inkMuted)
        }
    }

    private func yourCrew(_ crew: Aloft_V1_Crew) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            FieldBox {
                Stamp("Crew code")
                Text(crew.code.map(String.init).joined(separator: " "))
                    .font(.custom("IBMPlexMono-Light", size: 22))
                    .foregroundStyle(Palette.ink)
                Spacer()
                ShareLink(item: "Rise with me on Aloft. Our Crew code is \(crew.code).") {
                    Text("Invite")
                }
                .buttonStyle(.chip(.lampOutline))
            }
            ForEach(crew.members, id: \.userID) { member in
                HStack(spacing: Space.s3) {
                    Avatar(name: member.firstName)
                    Text(member.firstName.isEmpty ? "New member" : member.firstName)
                        .textStyle(.body).foregroundStyle(Palette.ink)
                    Spacer()
                }
                .frame(minHeight: 52)
            }
        }
    }
}

// MARK: 06 Nights

struct NightsStep: View {
    enum Which { case bedtime, wake }

    @Environment(AppModel.self) private var model
    @State private var editing: Which?

    var body: some View {
        OnboardingScreen(
            step: .nights,
            stamp: "0.8 Nights",
            title: "Set your nights.",
            subtitle: "Aloft learns your rhythm from here. You can change these later.",
            lead: { EmptyView() },
            work: {
                Grid(horizontalSpacing: Space.s3) {
                    GridRow {
                        tile("Bedtime", minutes: model.draft.bedtimeMinutes, which: .bedtime)
                        tile("Wake", minutes: model.draft.wakeMinutes, which: .wake)
                    }
                }
                if let editing {
                    Card(padding: Space.s3) {
                        DatePicker("", selection: binding(editing), displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "en_GB"))
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
                Card(padding: 20) {
                    HStack(spacing: Space.s4) {
                        Image(systemName: "moon.stars")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Palette.inkMuted)
                            .frame(width: 48)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Space.s1) {
                            Text("Wear it to bed.").textStyle(.body).foregroundStyle(Palette.ink)
                            Text("Your band reads your night. Aloft turns it into tomorrow’s sky.")
                                .textStyle(.small).foregroundStyle(Palette.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let error = model.error {
                    Text(error).textStyle(.small).foregroundStyle(Palette.ember)
                }
            },
            action: PrimaryAction(title: "Finish", busy: model.busy) { Task { await model.finishOnboarding() } }
        )
    }

    private func tile(_ label: String, minutes: Int, which: Which) -> some View {
        Button { editing = editing == which ? nil : which } label: {
            VStack(alignment: .leading, spacing: 6) {
                Stamp(label)
                Text(String(format: "%02d:%02d", minutes / 60, minutes % 60))
                    .textStyle(.readoutLG)
                    .foregroundStyle(Palette.ink)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(editing == which ? Palette.ink : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%02d:%02d", minutes / 60, minutes % 60))
    }

    private func binding(_ which: Which) -> Binding<Date> {
        Binding {
            let m = which == .bedtime ? model.draft.bedtimeMinutes : model.draft.wakeMinutes
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
        } set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            if which == .bedtime { model.draft.bedtimeMinutes = m } else { model.draft.wakeMinutes = m }
        }
    }
}
