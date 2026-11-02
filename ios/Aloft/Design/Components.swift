import SwiftUI

// MARK: Buttons

/// Pill buttons from the design: primary (ink), ghost (outlined), lamp (a
/// person-to-person action), and lamp outline. `compact` is the 36pt chip.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, lamp, lampOutline }
    var kind: Kind = .primary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("HostGrotesk-Medium", size: compact ? 14 : 16))
            .lineLimit(1)
            .padding(.horizontal, compact ? 16 : 24)
            .frame(maxWidth: compact ? nil : .infinity)
            .frame(height: compact ? 36 : 52)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay {
                switch kind {
                case .ghost: Capsule().strokeBorder(Palette.lineStrong, lineWidth: 1)
                case .lampOutline: Capsule().strokeBorder(Palette.lamp, lineWidth: 1)
                default: EmptyView()
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .frame(minHeight: 44)
    }

    private var foreground: Color {
        switch kind {
        case .primary: Palette.ground
        case .ghost: Palette.ink
        case .lamp: Palette.onLamp
        case .lampOutline: Palette.lamp
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Palette.ink
        case .lamp: Palette.lamp
        default: .clear
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var primary: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var ghost: PillButtonStyle { PillButtonStyle(kind: .ghost) }
    static var lamp: PillButtonStyle { PillButtonStyle(kind: .lamp) }
    static func chip(_ kind: PillButtonStyle.Kind) -> PillButtonStyle { PillButtonStyle(kind: kind, compact: true) }
}

/// The quiet text button used for Back and the cross-link in the top bar.
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.small)
            .foregroundStyle(Palette.inkMuted)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == LinkButtonStyle {
    static var link: LinkButtonStyle { LinkButtonStyle() }
}

/// A disabled primary button keeps its shape but dims.
struct PrimaryAction: View {
    let title: String
    var busy = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if busy { ProgressView().tint(Palette.ground) } else { Text(title) }
        }
        .buttonStyle(.primary)
        .disabled(!enabled || busy)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: Surfaces

struct Card<Content: View>: View {
    var padding: CGFloat = Space.s5
    var fill: Color = Palette.raised
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Text(name.first.map { String($0).uppercased() } ?? "·")
            .font(.custom("HostGrotesk-Medium", size: 15))
            .foregroundStyle(Palette.lamp)
            .frame(width: size, height: size)
            .background(Palette.lampTint, in: Circle())
            .accessibilityHidden(true)
    }
}

/// The recessed input container. `focused` draws the sky focus ring.
struct FieldBox<Content: View>: View {
    var focused = false
    var height: CGFloat = 56
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Space.s3) { content }
            .padding(.horizontal, Space.s4)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.lineStrong, lineWidth: 1))
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: Radius.md + 4, style: .continuous)
                        .strokeBorder(Palette.sky, lineWidth: 2)
                        .padding(-4)
                }
            }
    }
}

// MARK: Number entry

struct NumberPad: View {
    var keyHeight: CGFloat = 48
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        Grid(horizontalSpacing: Space.s2, verticalSpacing: Space.s2) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in key(row * 3 + col) }
                }
            }
            GridRow {
                Color.clear.frame(height: keyHeight)
                key(0)
                Button(action: onDelete) {
                    Text("DEL").textStyle(.stamp).foregroundStyle(Palette.inkMuted)
                        .frame(maxWidth: .infinity, minHeight: keyHeight)
                        .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .accessibilityLabel("Delete")
            }
        }
        .buttonStyle(KeyPressStyle())
    }

    private func key(_ digit: Int) -> some View {
        Button { onDigit(digit) } label: {
            Text("\(digit)")
                .font(.custom("IBMPlexMono-Light", fixedSize: 24))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: keyHeight)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Six code cells. The next empty cell carries the focus ring.
struct CodeCells: View {
    let digits: [Int]
    var length = 6
    var cellHeight: CGFloat = 60

    var body: some View {
        HStack(spacing: Space.s2) {
            ForEach(0..<length, id: \.self) { i in
                Text(i < digits.count ? "\(digits[i])" : "")
                    .font(.custom("IBMPlexMono-Light", fixedSize: 30))
                    .foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: cellHeight)
                    .background(Palette.well, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(i == digits.count ? Palette.lineStrong : Palette.line, lineWidth: 1))
                    .overlay {
                        if i == digits.count {
                            RoundedRectangle(cornerRadius: Radius.md + 4, style: .continuous)
                                .strokeBorder(Palette.sky, lineWidth: 2).padding(-4)
                        }
                    }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Verification code")
        .accessibilityValue(digits.map(String.init).joined())
    }
}

// MARK: Rows and toggles

/// A selectable row: a stamp on the left, a readout on the right.
struct ValueRow: View {
    let label: String
    let value: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Stamp(label)
                Spacer()
                Text(value).textStyle(.readout).foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, Space.s4)
            .frame(minHeight: 52)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(selected ? Palette.ink : .clear, lineWidth: 1))
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityValue(value)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SkyToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) { Text(title).textStyle(.body).foregroundStyle(Palette.ink) }
            .toggleStyle(SkyToggleStyle())
            .frame(minHeight: 48)
    }
}

private struct SkyToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack {
                configuration.label
                Spacer()
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule().fill(configuration.isOn ? Palette.sky : Palette.well)
                        .overlay(Capsule().strokeBorder(configuration.isOn ? .clear : Palette.lineStrong, lineWidth: 1))
                    Circle().fill(configuration.isOn ? Palette.onSky : Palette.inkMuted)
                        .frame(width: 25, height: 25).padding(3)
                }
                .frame(width: 51, height: 31)
                .animation(.snappy(duration: 0.2), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// "01 02 03 04 05 06": done steps muted, the current one ink.
struct StepDots: View {
    let current: Int
    var total = 6

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...total, id: \.self) { step in
                Stamp(String(format: "%02d", step), color: step == current ? Palette.ink : step < current ? Palette.inkMuted : Palette.inkFaint)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current) of \(total)")
    }
}

// MARK: Instruments

/// The Ceiling gauge: 10pt ticks, sky ticks up to the load, a sky marker.
struct CeilingScale: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .bottomLeading) {
                Ticks(spacing: 10, color: Palette.lineStrong).frame(height: 8)
                Ticks(spacing: 10, color: Palette.sky).frame(width: x, height: 8).clipped()
                Rectangle().fill(Palette.sky).frame(width: 2, height: 16).offset(x: x - 1)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}

private struct Ticks: View {
    let spacing: CGFloat
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            var x: CGFloat = 0
            while x <= size.width {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(color))
                x += spacing
            }
        }
    }
}

/// A horizontal ruler with a fixed center needle. Drag to change the value.
struct Ruler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Value per minor tick.
    let step: Double
    var height: CGFloat = 40

    @State private var dragStart: Double?

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let mid = size.width / 2
                let minor: CGFloat = 12
                let firstTick = (value / step).rounded(.down)
                let offset = CGFloat((value / step) - firstTick) * minor
                var i = -Int(mid / minor) - 1
                while CGFloat(i) * minor < mid + minor {
                    let tickValue = (firstTick + Double(i)) * step
                    let x = mid + CGFloat(i) * minor - offset
                    if range.contains(tickValue) {
                        let major = Int((tickValue / step).rounded()) % 5 == 0
                        let h: CGFloat = major ? 24 : 10
                        ctx.fill(Path(CGRect(x: x, y: size.height - h, width: 1, height: h)), with: .color(Palette.lineStrong))
                    }
                    i += 1
                }
                ctx.fill(Path(CGRect(x: mid - 1, y: 0, width: 2, height: size.height)), with: .color(Palette.ink))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { g in
                    let start = dragStart ?? value
                    dragStart = start
                    let raw = start - Double(g.translation.width / 12) * step
                    value = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in dragStart = nil })
            .frame(width: geo.size.width)
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

// MARK: The Window

enum SkyKind: String {
    case day = "SkyDay", crew = "SkyCrew", night = "SkyNight"

    var fallback: Color {
        switch self {
        case .day: Color(hex: 0x2C5F96)
        case .crew: Color(hex: 0x56789A)
        case .night: Color(hex: 0x0C1626)
        }
    }
}

/// The pixel sky. Always hard pixels, fading out at the bottom into ground.
struct Window: View {
    var kind: SkyKind = .day
    var fades = true

    var body: some View {
        kind.fallback
            .overlay {
                Image(kind.rawValue)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .mask {
                if fades {
                    LinearGradient(stops: [.init(color: .black, location: 0.45), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle()
                }
            }
            .accessibilityHidden(true)
    }
}

// MARK: Tabs

enum HomeTab: String, CaseIterable, Identifiable {
    case sky = "Sky", crew = "Crew", log = "Log", you = "You"
    var id: String { rawValue }
}

/// A floating pill when narrow, a vertical rail on the inner display.
struct TabPill: View {
    @Binding var selection: HomeTab
    var vertical = false

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(HomeTab.allCases) { tab in
                Button { selection = tab } label: {
                    Text(tab.rawValue)
                        .font(.custom("HostGrotesk-Medium", size: 14))
                        .foregroundStyle(selection == tab ? Palette.ground : Palette.inkMuted)
                        .frame(width: vertical ? 60 : nil, height: vertical ? 48 : 44)
                        .frame(minWidth: vertical ? nil : 64)
                        .padding(.horizontal, vertical ? 0 : 14)
                        .background(selection == tab ? Palette.ink : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Palette.raised, in: Capsule())
        .shadow(color: Palette.shadow, radius: 16, y: 12)
    }
}
