import Foundation

/// Neon Auth (Managed Better Auth) over its REST API.
///
/// Sign-in is passwordless: email one-time code, or Sign in with Apple via an
/// identity token. Better Auth keeps the session in cookies, so this client
/// stores the cookies it is handed in the Keychain and replays them. The Go
/// API wants a short-lived JWT, which `/get-session` returns in the
/// `set-auth-jwt` header.
actor NeonAuth {
    enum AuthError: LocalizedError {
        case server(String)
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case let .server(message): message
            case .notSignedIn: "You're signed out."
            }
        }
    }

    struct User: Decodable, Sendable {
        let id: String
        let email: String?
        let name: String?
    }

    private let baseURL: URL
    private let origin: String
    private let session: URLSession
    private var cookies: [HTTPCookie]
    private var jwt: (token: String, expires: Date)?

    private static let cookieAccount = "neon-auth-cookies"

    init(baseURL: URL, origin: String) {
        self.baseURL = baseURL
        self.origin = origin
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
        cookies = Self.loadCookies()
    }

    var isSignedIn: Bool { !cookies.isEmpty }

    func sendCode(to email: String) async throws {
        _ = try await post("email-otp/send-verification-otp", ["email": email, "type": "sign-in"])
    }

    /// Signs in, creating the account on first use.
    func verify(email: String, code: String) async throws {
        _ = try await post("sign-in/email-otp", ["email": email, "otp": code])
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        _ = try await post("sign-in/social", [
            "provider": "apple",
            "idToken": ["token": identityToken, "nonce": nonce],
        ])
    }

    func signOut() async {
        _ = try? await post("sign-out", [:])
        clear()
    }

    func clear() {
        cookies = []
        jwt = nil
        Keychain.set(nil, for: Self.cookieAccount)
    }

    /// A bearer token for the Aloft API, refreshed a minute before it expires.
    func accessToken() async throws -> String {
        if let jwt, jwt.expires.timeIntervalSinceNow > 60 { return jwt.token }
        guard isSignedIn else { throw AuthError.notSignedIn }
        var request = URLRequest(url: baseURL.appending(path: "get-session"))
        applyHeaders(&request)
        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        absorbCookies(http)
        guard http.statusCode == 200, let token = http.value(forHTTPHeaderField: "set-auth-jwt"), !token.isEmpty else {
            if http.statusCode == 401 || String(data: data, encoding: .utf8) == "null" { clear() }
            throw AuthError.notSignedIn
        }
        jwt = (token, Self.expiry(of: token) ?? .now.addingTimeInterval(14 * 60))
        return token
    }

    // MARK: Plumbing

    private func post(_ path: String, _ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        applyHeaders(&request)
        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        absorbCookies(http)
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.message
            throw AuthError.server(message ?? "Sign-in failed (\(http.statusCode)).")
        }
        return data
    }

    private func applyHeaders(_ request: inout URLRequest) {
        // Better Auth checks Origin on cookie-bearing requests.
        request.setValue(origin, forHTTPHeaderField: "Origin")
        for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func absorbCookies(_ response: HTTPURLResponse) {
        guard let fields = response.allHeaderFields as? [String: String], let url = response.url else { return }
        let fresh = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !fresh.isEmpty else { return }
        var byName = Dictionary(cookies.map { ($0.name, $0) }, uniquingKeysWith: { $1 })
        for cookie in fresh {
            if let expires = cookie.expiresDate, expires < .now {
                byName[cookie.name] = nil
            } else {
                byName[cookie.name] = cookie
            }
        }
        cookies = Array(byName.values)
        saveCookies()
    }

    private func saveCookies() {
        let stored = cookies.compactMap { $0.properties }.map { props in
            props.reduce(into: [String: String]()) { out, pair in
                out[pair.key.rawValue] = (pair.value as? Date).map { String($0.timeIntervalSince1970) } ?? "\(pair.value)"
            }
        }
        Keychain.set(try? JSONEncoder().encode(stored), for: Self.cookieAccount)
    }

    private static func loadCookies() -> [HTTPCookie] {
        guard let data = Keychain.get(cookieAccount),
              let stored = try? JSONDecoder().decode([[String: String]].self, from: data) else { return [] }
        return stored.compactMap { raw in
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in raw {
                let k = HTTPCookiePropertyKey(key)
                props[k] = k == .expires ? Double(value).map(Date.init(timeIntervalSince1970:)) : value
            }
            return HTTPCookie(properties: props)
        }
    }

    private static func expiry(of jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let data = Data(base64Encoded: b64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }

    private struct ServerMessage: Decodable { let message: String? }
}
