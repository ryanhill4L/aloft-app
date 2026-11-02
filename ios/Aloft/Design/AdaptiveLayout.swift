import SwiftUI

/// How a screen splits, decided only by the space the window has (Apple's
/// iPhone Duo guidance; docs/design.md). No hinge angle, posture enum, or
/// device check: a wide normal iPhone in landscape gets the side-by-side
/// layout too.
enum PaneSplit: Equatable {
    /// One column. Closed Duo, a normal iPhone in portrait.
    case single
    /// Two panes left and right: read on the left, act on the right.
    case sideBySide
    /// Two panes above and below: the picture above, the work below.
    case stacked

    init(_ size: CGSize) {
        if size.width >= 700, size.width > size.height {
            self = .sideBySide
        } else if size.width >= 600, size.height > size.width {
            self = .stacked
        } else {
            self = .single
        }
    }
}

private struct PaneSplitKey: EnvironmentKey {
    static let defaultValue = PaneSplit.single
}

extension EnvironmentValues {
    var paneSplit: PaneSplit {
        get { self[PaneSplitKey.self] }
        set { self[PaneSplitKey.self] = newValue }
    }
}

/// Reads the window's size and publishes the split to every child.
struct AdaptiveRoot<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            content.environment(\.paneSplit, PaneSplit(geo.size))
        }
    }
}

/// The frame every sign-up and onboarding screen shares. `lead` is the
/// reading side (stamp, title, explanation); `work` is the doing side
/// (fields, pads, choices). One column stacks them; wider windows split them
/// across the fold the way the design's Open and Open vertical boards do.
struct StepScreen<Trailing: View, Lead: View, Work: View>: View {
    let stamp: String
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var lead: Lead
    @ViewBuilder var work: Work
    let action: PrimaryAction

    @Environment(\.paneSplit) private var split

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            switch split {
            case .single: single
            case .sideBySide: sideBySide
            case .stacked: stacked
            }
        }
    }

    private var topBar: some View {
        HStack {
            if let onBack {
                Button("Back", action: onBack).buttonStyle(.link)
            }
            Spacer()
            trailing
        }
    }

    private func heading(display: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Stamp(stamp)
            Text(title)
                .textStyle(display ? .display : .title)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .textStyle(display ? .body : .small)
                    .foregroundStyle(Palette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var single: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            topBar
            heading(display: false)
            lead
            work
            action
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s2)
        .padding(.bottom, Space.s3)
    }

    private var sideBySide: some View {
        HStack(alignment: .top, spacing: 64) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                heading(display: true).padding(.top, Space.s5)
                lead
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Space.s4) {
                work
                action
            }
            .padding(.top, 72)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, Space.s5)
    }

    private var stacked: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    topBar
                    heading(display: true).padding(.top, Space.s3)
                    lead
                    Spacer(minLength: 0)
                }
                .frame(height: geo.size.height / 2 - 28)
                Spacer().frame(height: 56)
                VStack(alignment: .leading, spacing: Space.s4) {
                    work
                    action
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, Space.s6)
        .padding(.vertical, Space.s3)
    }
}

extension StepScreen where Trailing == EmptyView {
    init(stamp: String, title: String, subtitle: String? = nil, onBack: (() -> Void)? = nil,
         @ViewBuilder lead: () -> Lead, @ViewBuilder work: () -> Work, action: PrimaryAction) {
        self.init(stamp: stamp, title: title, subtitle: subtitle, onBack: onBack, trailing: { EmptyView() }, lead: lead, work: work, action: action)
    }
}
