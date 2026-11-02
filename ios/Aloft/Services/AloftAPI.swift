import Connect
import Foundation

/// The Aloft profile API (proto/aloft/v1/aloft.proto). Health numbers never
/// go through here; only profile, Crew, the weather word, and Lifts.
struct AloftAPI: Sendable {
    let client: Aloft_V1_AloftServiceClientInterface

    init(baseURL: URL, auth: NeonAuth) {
        let protocolClient = ProtocolClient(
            httpClient: URLSessionHTTPClient(),
            config: ProtocolClientConfig(
                host: baseURL.absoluteString,
                networkProtocol: .connect,
                codec: ProtoCodec(),
                interceptors: [InterceptorFactory { _ in BearerInterceptor(auth: auth) }]
            )
        )
        client = Aloft_V1_AloftServiceClient(client: protocolClient)
    }

    init(client: Aloft_V1_AloftServiceClientInterface) {
        self.client = client
    }

    func me() async throws -> Aloft_V1_Profile {
        try await client.getMe(request: .init(), headers: [:]).unwrap().profile
    }

    func save(_ profile: Aloft_V1_Profile) async throws -> Aloft_V1_Profile {
        var req = Aloft_V1_UpdateProfileRequest()
        req.profile = profile
        return try await client.updateProfile(request: req, headers: [:]).unwrap().profile
    }

    func createCrew() async throws -> Aloft_V1_Crew {
        try await client.createCrew(request: .init(), headers: [:]).unwrap().crew
    }

    func joinCrew(code: String) async throws -> Aloft_V1_Crew {
        var req = Aloft_V1_JoinCrewRequest()
        req.code = code
        return try await client.joinCrew(request: req, headers: [:]).unwrap().crew
    }

    func crew(on day: Date) async throws -> Aloft_V1_Crew? {
        var req = Aloft_V1_GetCrewRequest()
        req.day = Self.dayString(day)
        let res = try await client.getCrew(request: req, headers: [:]).unwrap()
        return res.hasCrew ? res.crew : nil
    }

    func share(_ weather: Aloft_V1_Weather, on day: Date) async throws {
        var req = Aloft_V1_SetWeatherRequest()
        req.day = Self.dayString(day)
        req.weather = weather
        _ = try await client.setWeather(request: req, headers: [:]).unwrap()
    }

    func sendLift(to userID: String, message: String) async throws -> Aloft_V1_Lift {
        var req = Aloft_V1_SendLiftRequest()
        req.toUserID = userID
        req.message = message
        return try await client.sendLift(request: req, headers: [:]).unwrap().lift
    }

    func lifts() async throws -> [Aloft_V1_Lift] {
        try await client.listLifts(request: .init(), headers: [:]).unwrap().lifts
    }

    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension ResponseMessage {
    func unwrap() throws -> Output {
        switch result {
        case let .success(output): return output
        case let .failure(error): throw APIError(message: error.message ?? "The Aloft server didn't answer.")
        }
    }
}

private final class BearerInterceptor: UnaryInterceptor, @unchecked Sendable {
    private let auth: NeonAuth

    init(auth: NeonAuth) { self.auth = auth }

    func handleUnaryRequest<Message: ProtobufMessage>(
        _ request: HTTPRequest<Message>,
        proceed: @escaping @Sendable (Result<HTTPRequest<Message>, ConnectError>) -> Void
    ) {
        Task {
            do {
                let token = try await auth.accessToken()
                var headers = request.headers
                headers["Authorization"] = ["Bearer \(token)"]
                proceed(.success(HTTPRequest(url: request.url, headers: headers, message: request.message, method: request.method, trailers: request.trailers, idempotencyLevel: request.idempotencyLevel)))
            } catch {
                proceed(.failure(ConnectError(code: .unauthenticated, message: "Sign in again to continue.")))
            }
        }
    }
}
