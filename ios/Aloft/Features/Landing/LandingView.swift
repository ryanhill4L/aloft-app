import SwiftUI

/// 01 Landing. The Window on top, the promise and two doors below.
struct LandingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneSplit) private var split

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Palette.ground.ignoresSafeArea()
                Window(kind: .day)
                    .frame(height: windowHeight(geo.size) + geo.safeAreaInsets.top)
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea()
                skyStamps
                    .padding(.horizontal, split == .single ? Space.s5 : 40)
                    .padding(.top, Space.s2)
                content
            }
        }
    }

    private func windowHeight(_ size: CGSize) -> CGFloat {
        switch split {
        case .single: size.height * 0.56
        case .sideBySide: size.height * 0.72
        case .stacked: size.height * 0.5
        }
    }

    private var skyStamps: some View {
        HStack {
            Stamp("0.0 Aloft", color: Palette.onWindow)
            Spacer()
            Stamp(split == .sideBySide ? "Alt 000 · One sky" : "Alt 000", color: Palette.onWindow)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch split {
        case .single:
            VStack(alignment: .leading, spacing: Space.s5) {
                Spacer()
                VStack(alignment: .leading, spacing: Space.s3) {
                    Stamp("Aloft")
                    title(.display)
                    Text("Track your recovery under one sky, with the people who keep you going.")
                        .textStyle(.body).foregroundStyle(Palette.inkMuted)
                }
                VStack(spacing: Space.s3) { doors }
                bandCheck
            }
            .padding(.horizontal, Space.s5)
            .padding(.bottom, Space.s3)
        case .sideBySide:
            HStack(alignment: .bottom, spacing: 64) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Stamp("Aloft")
                    title(.displayXL)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: Space.s5) {
                    pitch
                    HStack(spacing: Space.s3) { doors }
                    bandCheck
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.horizontal, 40)
            .padding(.bottom, Space.s5)
        case .stacked:
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: Space.s4) {
                    Stamp("Aloft")
                    title(.displayXL)
                    pitch
                    Spacer()
                    HStack(spacing: Space.s3) { doors }
                    bandCheck
                }
                .padding(.top, geo.size.height / 2 + 28)
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s3)
            }
        }
    }

    private func title(_ style: TextStyle) -> some View {
        Text("Nobody rises alone.")
            .textStyle(style)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var pitch: some View {
        (Text("A recovery tracker built around other people. ").foregroundStyle(Palette.ink)
            + Text("Your sky shows how ready you are. Your Crew shares it with you.").foregroundStyle(Palette.inkMuted))
            .textStyle(.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var bandCheck: some View {
        Button("Check your band") { model.route = .bandCheck }
            .buttonStyle(.link)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var doors: some View {
        Button("Create account") { model.route = .email(.signUp) }.buttonStyle(.primary)
        Button("Sign in") { model.route = .email(.signIn) }.buttonStyle(.ghost)
    }
}
