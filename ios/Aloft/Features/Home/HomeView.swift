import SwiftUI

/// 11 Home: Sky, Crew, Log, You. A floating pill when the window is narrow,
/// a vertical rail on the right edge when it is wide or tall.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split
    @State private var tab: HomeTab = .sky

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: split == .single ? .bottom : .topTrailing) {
                Palette.ground.ignoresSafeArea()
                Group {
                    switch tab {
                    case .sky: SkyTab()
                    case .crew: CrewTab()
                    case .log: LogTab()
                    case .you: YouTab()
                    }
                }
                // Sky draws under the rail itself and insets only its words.
                .padding(.trailing, split == .single || tab == .sky ? 0 : 92)
                .padding(.bottom, split == .single ? 76 : 0)

                TabPill(selection: $tab, vertical: split != .single)
                    .padding(split == .single ? .bottom : .trailing, split == .single ? Space.s2 : Space.s4)
                    // Tall: on the ground just below the horizon line.
                    .padding(.top, split == .stacked ? geo.size.height / 2 + Space.s4 : split == .sideBySide ? 40 : 0)
            }
        }
        .task { await model.refreshHome() }
    }
}

// MARK: Sky

struct SkyTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split

    private var today: Today { model.today }

    var body: some View {
        GeometryReader { geo in
            switch split {
            case .single: single(geo.size)
            case .sideBySide: sideBySide(geo.size)
            case .stacked: stacked(geo.size)
            }
        }
    }

    // Closed: the porthole. One Window, one number, one action.
    private func single(_ size: CGSize) -> some View {
        ZStack(alignment: .top) {
            // The sky stays put and runs under the status strip; the reading scrolls.
            Window(kind: .day)
                .frame(height: size.height * 0.43 + 60)
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    skyStamps("0.1 Recovery")
                    Spacer().frame(height: size.height * 0.43 - 128)
                    score
                    sentence(long: true)
                    ceiling("0.2 Ceiling")
                    crewStrip
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)
            }
            .scrollIndicators(.hidden)
        }
    }

    // Open: the Window on the left page; read left, act right.
    private func sideBySide(_ size: CGSize) -> some View {
        HStack(alignment: .top, spacing: Space.s6) {
            ZStack(alignment: .top) {
                Window(kind: .day).frame(height: size.height * 0.58).ignoresSafeArea(edges: [.top, .leading])
                VStack(alignment: .leading, spacing: Space.s4) {
                    skyStamps("0.1 Recovery").padding(.top, Space.s5)
                    Spacer()
                    score
                    sentence(long: true)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, Space.s5)
            }
            .frame(width: size.width / 2)
            // A short window (a phone in landscape) scrolls instead of clipping.
            ViewThatFits(in: .vertical) {
                rightPage
                ScrollView { rightPage }.scrollIndicators(.hidden)
            }
            .padding(.vertical, Space.s5)
            .padding(.trailing, 92)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var rightPage: some View {
        VStack(alignment: .leading, spacing: Space.s5) {
            ceiling("0.2 Ceiling")
            Grid(alignment: .leading, horizontalSpacing: Space.s4) {
                GridRow {
                    metric("0.3 Sleep", sleepText, style: .readoutLG, color: Palette.sky)
                    metric("HRV · ms", hrvText, style: .readoutLG)
                }
            }
            HStack {
                Stamp("Resting heart")
                Spacer()
                Text(restingText).textStyle(.readout).foregroundStyle(Palette.ink)
            }
            .padding(.top, Space.s3)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            Spacer()
            VStack(alignment: .leading, spacing: Space.s3) {
                Stamp("0.4 Crew · \(model.crew?.members.count ?? 0) under your sky")
                liftCard(reply: true)
            }
        }
    }

    // Open vertical: the hinge is the horizon. Sky above, instruments below.
    private func stacked(_ size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                Window(kind: .day).frame(height: size.height * 0.4)
                VStack(alignment: .leading) {
                    skyStamps("0.1 Recovery").padding(.top, Space.s5)
                    Spacer()
                    score
                }
                .padding(.horizontal, Space.s6)
            }
            .frame(height: size.height / 2 - 8)
            VStack(alignment: .leading, spacing: 20) {
                sentence(long: true)
                ceiling("0.2 Ceiling")
                Grid(alignment: .leading, horizontalSpacing: Space.s3) {
                    GridRow {
                        metric("Sleep", sleepText, style: .readout, color: Palette.sky)
                        metric("HRV", hrvText == "---" ? "---" : "\(hrvText) MS", style: .readout)
                        metric("Resting", restingText, style: .readout)
                    }
                }
                Spacer(minLength: 0)
                liftCard(reply: false)
            }
            .padding(.leading, Space.s6)
            .padding(.trailing, 92 + Space.s4)
            .padding(.top, Space.s7)
            .padding(.bottom, Space.s5)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Pieces

    private func skyStamps(_ label: String) -> some View {
        HStack {
            Stamp(label, color: Palette.onWindow)
            Spacer()
            Stamp(Self.dateStamp.string(from: .now), color: Palette.onWindow)
        }
    }

    private var score: some View {
        HStack(alignment: .bottom) {
            Text(today.recovery.map { String(format: "%03d", $0) } ?? "---")
                .textStyle(.readoutXL)
                .foregroundStyle(today.recovery == nil ? Palette.inkFaint : Palette.ink)
                .accessibilityLabel(today.recovery.map { "Recovery \($0) percent, estimate" } ?? "No recovery reading yet")
            Spacer()
            VStack(alignment: .trailing, spacing: Space.s1) {
                Stamp("Weather")
                Text(today.weather?.rawValue ?? "Not yet")
                    .textStyle(.heading)
                    .foregroundStyle(color(for: today.weather))
            }
            .padding(.bottom, 10)
        }
    }

    private func sentence(long: Bool) -> some View {
        let (lead, rest) = Self.copy(for: today.weather)
        return (Text(lead + " ").foregroundStyle(Palette.ink) + Text(rest).foregroundStyle(Palette.inkMuted))
            .textStyle(.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func ceiling(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Stamp(label)
                Spacer()
                if let load = today.load, let ceiling = today.ceiling {
                    (Text("LOAD \(String(format: "%04.1f", load))").foregroundStyle(Palette.sky)
                        + Text(" / \(String(format: "%.1f", ceiling))").foregroundStyle(Palette.inkFaint))
                        .textStyle(.stamp)
                } else {
                    Stamp("No load yet")
                }
            }
            CeilingScale(fraction: (today.load ?? 0) / max(today.ceiling ?? 1, 1))
        }
        .accessibilityElement(children: .combine)
    }

    private var crewStrip: some View {
        HStack(spacing: Space.s3) {
            Stamp("0.3 Crew").frame(width: 64, alignment: .leading)
            if let members = model.crew?.members.filter({ $0.userID != model.profile.userID }), !members.isEmpty {
                HStack(spacing: 6) { ForEach(members.prefix(4), id: \.userID) { Avatar(name: $0.firstName) } }
                RoundedRectangle(cornerRadius: Radius.sm).fill(Palette.raised).frame(height: 12)
            } else {
                Text("Start a Crew from the Crew tab.").textStyle(.small).foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private func metric(_ label: String, _ value: String, style: TextStyle, color: Color = Palette.ink) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Stamp(label)
            Text(value).textStyle(style).foregroundStyle(value == "---" ? Palette.inkFaint : color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func liftCard(reply: Bool) -> some View {
        if let lift = model.lifts.first {
            VStack(alignment: .leading, spacing: Space.s3) {
                if !reply { Stamp("0.3 Crew · \(lift.fromFirstName) · \(Self.time(lift.sentAtUnix))", color: Palette.lamp) }
                Text(lift.message).textStyle(.voiceSmall).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if reply {
                    HStack {
                        Stamp("\(lift.fromFirstName) · \(Self.time(lift.sentAtUnix))", color: Palette.lamp)
                        Spacer()
                        Text("Reply").font(.custom("HostGrotesk-Medium", size: 14)).foregroundStyle(Palette.lamp)
                            .padding(.horizontal, 16).frame(height: 36)
                            .overlay(Capsule().strokeBorder(Palette.lamp, lineWidth: 1))
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.lampTint, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        } else {
            Card {
                Text("When someone in your Crew sends a Lift, it lands here.")
                    .textStyle(.small).foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private var sleepText: String {
        guard let s = today.health.sleep else { return "---" }
        let minutes = Int(s / 60)
        return "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }

    private var hrvText: String { today.health.hrvMs.map { String(format: "%03.0f", $0) } ?? "---" }
    private var restingText: String { today.health.restingBPM.map { "\(Int($0.rounded())) BPM" } ?? "---" }

    static func copy(for weather: Weather?) -> (String, String) {
        switch weather {
        case .clear: ("A clear morning.", "You slept well and your heart is steady, so today can hold more.")
        case .fair: ("A fair morning.", "Some cloud about. Take today at a steady pace.")
        case .overcast: ("An overcast morning.", "Your body is still catching up. Go easy, and rest well tonight.")
        case nil: ("No reading yet.", "Wear your band tonight and Aloft will read your sky in the morning.")
        }
    }

    /// "Mon 02 Nov", as on the design.
    static let dateStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE dd MMM"
        return f
    }()

    static func time(_ unix: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(unix)).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}

func color(for weather: Weather?) -> Color {
    switch weather {
    case .clear: Palette.sky
    case .fair: Palette.fair
    case .overcast: Palette.overcast
    case nil: Palette.inkFaint
    }
}
