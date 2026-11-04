#if DEBUG
import AloftStrap
import SwiftUI

/// DEBUG screenshot fixtures: the sample people and numbers from the design
/// canvas, so every screen can be checked in the Simulator without an account
/// or a strap. Release builds never reach this (AppConfig.previewScreen).
enum Preview {
    @MainActor
    static func apply(_ screen: String, to model: AppModel) {
        model.draft.firstName = "Ryan"
        model.profile.firstName = "Ryan"
        model.profile.userID = "preview-ryan"
        model.today = Today(recovery: 82, load: 6.1, ceiling: 14.2, health: .init(sleep: 7 * 3600 + 42 * 60, hrvMs: 64, restingBPM: 52))
        model.crew = crew
        model.lifts = [lift]
        switch screen {
        case "landing": model.route = .landing
        case "signup": model.route = .email(.signUp)
        case "signin": model.route = .email(.signIn)
        case "verify": model.route = .verify(email: "ryan@example.com", mode: .signUp)
        case "name": model.route = .onboarding(.name)
        case "basics": model.route = .onboarding(.basics)
        case "band": model.route = .onboarding(.band)
        case "bandcheck": model.route = .bandCheck
        case "wake":
            model.route = .wake
            model.strap.previewWake(hour: 7, minute: 0)
        case "recap":
            model.route = .recap
            model.recap = MorningRecap(
                asleepSeconds: (7 * 60 + 12) * 60,
                efficiency: 0.86,
                onsetMs: 1_762_250_400_000,
                wakeMs: 1_762_276_800_000,
                restingBPM: 48,
                averageBPM: 52,
                stageNote: SleepNight.stageNote,
                hasStages: false
            )
        case "log":
            model.route = .home
            model.strap.previewPairingWait()
        case "health": model.route = .onboarding(.health)
        case "crew":
            model.crew = nil
            model.route = .onboarding(.crew)
        case "nights": model.route = .onboarding(.nights)
        case "home-empty":
            model.today = Today()
            model.crew = nil
            model.lifts = []
            model.route = .home
        default: model.route = .home
        }
    }

    /// `-AloftRenderBoards 1` renders every screen offscreen at the design's
    /// open Duo board sizes and writes PNGs to Documents/boards. Lets the
    /// unfolded layouts be checked without folding hardware.
    @MainActor
    static func renderBoards(into model: AppModel) async {
        let screens = ["landing", "signup", "verify", "name", "basics", "band", "health", "crew", "nights", "home", "home-empty"]
        let sizes = [("open", CGSize(width: 890, height: 626)), ("vertical", CGSize(width: 626, height: 890))]
        let dir = URL.documentsDirectory.appending(path: "boards")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for screen in screens {
            apply(screen, to: model)
            for (name, size) in sizes {
                let renderer = ImageRenderer(content: RootView()
                    .environment(model)
                    .frame(width: size.width, height: size.height)
                    .environment(\.colorScheme, .dark))
                renderer.scale = 2
                if let data = renderer.uiImage?.pngData() {
                    try? data.write(to: dir.appending(path: "\(screen)-\(name).png"))
                }
            }
        }
    }

    static var crew: Aloft_V1_Crew {
        var c = Aloft_V1_Crew()
        c.code = "K7M2QX"
        c.members = [
            member("preview-ryan", "Ryan", .clear),
            member("maya", "Maya", .clear),
            member("jonah", "Jonah", .fair),
            member("priya", "Priya", .overcast),
            member("theo", "Theo", .clear),
        ]
        return c
    }

    static var lift: Aloft_V1_Lift {
        var l = Aloft_V1_Lift()
        l.fromFirstName = "Maya"
        l.fromUserID = "maya"
        l.message = "You showed up on an overcast day. That counts."
        l.sentAtUnix = Int64(Calendar.current.date(bySettingHour: 7, minute: 12, second: 0, of: .now)!.timeIntervalSince1970)
        return l
    }

    private static func member(_ id: String, _ name: String, _ weather: Aloft_V1_Weather) -> Aloft_V1_CrewMember {
        var m = Aloft_V1_CrewMember()
        m.userID = id
        m.firstName = name
        m.weather = weather
        return m
    }
}
#endif
