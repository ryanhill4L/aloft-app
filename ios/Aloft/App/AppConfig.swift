import Foundation

/// Endpoints come from Info.plist, which the project spec fills from build
/// settings (ios/Config/*.xcconfig). Nothing secret lives here: the Neon Auth
/// URL is public by design.
enum AppConfig {
    static var apiURL: URL { url("AloftAPIURL", fallback: "http://localhost:9090") }
    static var neonAuthURL: URL { url("NeonAuthURL", fallback: "http://localhost:9091") }
    static var neonAuthOrigin: String { string("NeonAuthOrigin") ?? "http://localhost" }

    /// DEBUG only: `-AloftPreview <screen>` opens a screen with sample data and
    /// no network, for simulator screenshots. Never compiled into Release.
    static var previewScreen: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "AloftPreview")
        #else
        nil
        #endif
    }

    private static func string(_ key: String) -> String? {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func url(_ key: String, fallback: String) -> URL {
        URL(string: string(key) ?? fallback) ?? URL(string: fallback)!
    }
}
