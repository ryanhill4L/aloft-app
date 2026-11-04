import SwiftUI

@main
struct AloftApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .task(id: model.strap.lastSync) { await model.publishMorningRecap() }
                .onChange(of: scenePhase) { _, phase in
                    // Fold the WAL into the main file when leaving the foreground.
                    if phase == .background, let store = model.strap.store {
                        Task { try? await store.checkpointTruncate() }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        AdaptiveRoot {
            ZStack {
                Palette.ground.ignoresSafeArea()
                switch model.route {
                case .launching:
                    ProgressView().tint(Palette.inkMuted)
                case .landing:
                    LandingView()
                case let .email(mode):
                    EmailEntryView(mode: mode)
                case let .verify(email, mode):
                    VerifyCodeView(email: email, mode: mode)
                case let .onboarding(step):
                    OnboardingView(step: step)
                case .home:
                    HomeView()
                case .bandCheck:
                    BandCheckView()
                case .wake:
                    WakeView()
                case .recap:
                    RecapView()
                }
            }
            .animation(.smooth(duration: 0.25), value: model.route)
        }
        .tint(Palette.sky)
    }
}
