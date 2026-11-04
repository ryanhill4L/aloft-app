import AloftStrap
import Foundation
import Observation

enum EntryMode: Hashable { case signUp, signIn }

enum Route: Hashable {
    case launching
    case landing
    case email(EntryMode)
    case verify(email: String, mode: EntryMode)
    case onboarding(OnboardingStep)
    case home
    /// The strap debug screen, reachable without an account.
    case bandCheck
    /// Set the strap wake time. No phone alarm.
    case wake
}

enum OnboardingStep: Int, CaseIterable, Hashable {
    case name = 1, basics, band, health, crew, nights
}

/// The weather word a Crew sees. Recovery bands: Clear 67–100, Fair 34–66,
/// Overcast 0–33. A low day is weather, not failure.
enum Weather: String {
    case clear = "Clear", fair = "Fair", overcast = "Overcast"

    init(recovery: Int) {
        switch recovery {
        case 67...: self = .clear
        case 34...: self = .fair
        default: self = .overcast
        }
    }

    init?(_ wire: Aloft_V1_Weather) {
        switch wire {
        case .clear: self = .clear
        case .fair: self = .fair
        case .overcast: self = .overcast
        default: return nil
        }
    }

    var wire: Aloft_V1_Weather {
        switch self {
        case .clear: .clear
        case .fair: .fair
        case .overcast: .overcast
        }
    }
}

/// What onboarding collects before it is saved in one go on Finish.
struct OnboardingDraft: Equatable {
    var firstName = ""
    var birthYear = 1991
    var heightCM = 180.0
    var weightKG = 78.0
    var health = HealthAccess.Choices()
    var bedtimeMinutes = 22 * 60 + 30
    var wakeMinutes = 6 * 60 + 30
}

/// Today as the phone knows it. Every number traces to a stored row or a
/// Health sample; nil means missing and is shown as missing.
struct Today: Equatable {
    var recovery: Int?
    var load: Double?
    var ceiling: Double?
    var health = HealthAccess.Snapshot()

    var weather: Weather? { recovery.map(Weather.init(recovery:)) }
}

@MainActor
@Observable
final class AppModel {
    var route: Route = .launching
    var draft = OnboardingDraft()
    var profile = Aloft_V1_Profile()
    var crew: Aloft_V1_Crew?
    var lifts: [Aloft_V1_Lift] = []
    var today = Today()
    var error: String?
    var busy = false

    let auth: NeonAuth
    let api: AloftAPI
    let health = HealthAccess()
    let strap: StrapLink
    /// Preview mode never touches the network.
    let isPreview: Bool

    init() {
        auth = NeonAuth(baseURL: AppConfig.neonAuthURL, origin: AppConfig.neonAuthOrigin)
        api = AloftAPI(baseURL: AppConfig.apiURL, auth: auth)
        strap = StrapLink(
            store: try? StrapStore(url: Self.storeURL),
            trace: StrapTrace(directory: Self.storeURL.deletingLastPathComponent())
        )
        isPreview = AppConfig.previewScreen != nil
    }

    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "Aloft/\(StrapStore.fileName)")
    }

    func start() async {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "AloftRenderBoards") {
            await Preview.renderBoards(into: self)
        }
        if let screen = AppConfig.previewScreen {
            Preview.apply(screen, to: self)
            return
        }
        #endif
        guard await auth.isSignedIn else {
            route = .landing
            return
        }
        await loadProfileAndRoute()
    }

    // MARK: Auth

    func sendCode(to email: String, mode: EntryMode) async {
        await run {
            try await auth.sendCode(to: email)
            route = .verify(email: email, mode: mode)
        }
    }

    func resendCode(to email: String) async {
        await run { try await auth.sendCode(to: email) }
    }

    func verify(email: String, code: String) async {
        await run {
            try await auth.verify(email: email, code: code)
            await loadProfileAndRoute()
        }
    }

    func signInWithApple(identityToken: String, nonce: String) async {
        await run {
            try await auth.signInWithApple(identityToken: identityToken, nonce: nonce)
            await loadProfileAndRoute()
        }
    }

    func signOut() async {
        await auth.signOut()
        profile = .init()
        crew = nil
        lifts = []
        draft = OnboardingDraft()
        route = .landing
    }

    private func loadProfileAndRoute() async {
        do {
            profile = try await api.me()
            if profile.onboarded {
                route = .home
                await refreshHome()
            } else {
                draft.firstName = profile.firstName
                route = .onboarding(.name)
            }
        } catch {
            self.error = error.localizedDescription
            route = .landing
        }
    }

    // MARK: Onboarding

    func advance(from step: OnboardingStep) {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            route = .onboarding(next)
        }
    }

    func back(from step: OnboardingStep) {
        route = OnboardingStep(rawValue: step.rawValue - 1).map(Route.onboarding) ?? .landing
    }

    func requestHealth() async {
        try? await health.requestAccess(draft.health)
        advance(from: .health)
    }

    func createCrew() async {
        guard !isPreview else { return }
        await run { crew = try await api.createCrew() }
    }

    func joinCrew(code: String) async {
        guard !isPreview else { return }
        await run { crew = try await api.joinCrew(code: code) }
    }

    func finishOnboarding() async {
        var p = profile
        p.firstName = draft.firstName.trimmingCharacters(in: .whitespaces)
        p.birthYear = Int32(draft.birthYear)
        p.heightCm = Int32(draft.heightCM.rounded())
        p.weightKg = Int32(draft.weightKG.rounded())
        p.bedtimeMinutes = Int32(draft.bedtimeMinutes)
        p.wakeMinutes = Int32(draft.wakeMinutes)
        p.onboarded = true
        guard !isPreview else {
            profile = p
            route = .home
            return
        }
        await run {
            profile = try await api.save(p)
            route = .home
            await refreshHome()
        }
    }

    // MARK: Home

    func refreshHome() async {
        guard !isPreview else { return }
        today.health = await health.snapshot()
        if let weather = today.weather {
            try? await api.share(weather.wire, on: .now)
        }
        crew = (try? await api.crew(on: .now)) ?? crew
        lifts = (try? await api.lifts()) ?? lifts
    }

    func sendLift(to member: Aloft_V1_CrewMember, message: String) async -> Bool {
        guard !isPreview else { return true }
        var ok = false
        await run {
            _ = try await api.sendLift(to: member.userID, message: message)
            ok = true
        }
        return ok
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await work() } catch { self.error = error.localizedDescription }
    }
}
