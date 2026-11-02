import AuthenticationServices
import CryptoKit
import SwiftUI

/// 02 Sign up and 03 Sign in. Email gets a six-digit code; Apple signs in
/// directly. Both go through Neon Auth. No phone number.
struct EmailEntryView: View {
    let mode: EntryMode

    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var nonce = ""
    @FocusState private var focused: Bool

    private var isValid: Bool {
        let parts = email.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !email.contains(" ")
    }

    var body: some View {
        StepScreen(
            stamp: mode == .signUp ? "0.1 Sign up" : "0.1 Sign in",
            title: mode == .signUp ? "What’s your email?" : "Welcome back.",
            subtitle: mode == .signUp
                ? "We’ll send a 6-digit code to confirm it. No password to remember."
                : "Use the email you signed up with. We’ll send you a code.",
            onBack: { model.route = .landing },
            trailing: {
                Button(mode == .signUp ? "Sign in" : "Create account") {
                    model.route = .email(mode == .signUp ? .signIn : .signUp)
                }
                .buttonStyle(.link)
            },
            lead: { EmptyView() },
            work: {
                VStack(alignment: .leading, spacing: Space.s4) {
                    FieldBox(focused: focused) {
                        Stamp("Email")
                        Rectangle().fill(Palette.line).frame(width: 1, height: 24)
                        TextField("", text: $email, prompt: Text("you@example.com").foregroundStyle(Palette.inkFaint))
                            .font(.custom("IBMPlexMono-Light", size: 20))
                            .foregroundStyle(Palette.ink)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.send)
                            .focused($focused)
                            .onSubmit(send)
                            .accessibilityLabel("Email")
                    }
                    if let error = model.error {
                        Text(error).textStyle(.small).foregroundStyle(Palette.ember)
                    }
                    Spacer(minLength: Space.s4)
                    divider
                    SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
                        nonce = Self.randomNonce()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = Self.sha256(nonce)
                    } onCompletion: { result in
                        guard case let .success(auth) = result,
                              let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                              let tokenData = credential.identityToken,
                              let token = String(data: tokenData, encoding: .utf8) else { return }
                        if let given = credential.fullName?.givenName { model.draft.firstName = given }
                        Task { await model.signInWithApple(identityToken: token, nonce: nonce) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(Capsule())
                }
            },
            action: PrimaryAction(title: "Send code", busy: model.busy, enabled: isValid, action: send)
        )
        .onAppear {
            model.error = nil
            focused = true
        }
    }

    private var divider: some View {
        HStack(spacing: Space.s3) {
            Rectangle().fill(Palette.line).frame(height: 1)
            Stamp("Or")
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }

    private func send() {
        guard isValid else { return }
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        Task { await model.sendCode(to: address, mode: mode) }
    }

    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
