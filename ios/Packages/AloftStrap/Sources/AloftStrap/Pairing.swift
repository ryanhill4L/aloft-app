/// Lines and ATT checks for the 5/MG bond. CoreBluetooth stays in the app.
///
/// A confirmed write that comes back as insufficient authentication (5) or
/// insufficient encryption (15) is what makes iOS start pairing. The bytes of
/// the hello are not a key exchange. Cancelling the link on that error aborts
/// the prompt, so the refusal itself is not a reason to disconnect.
public enum StrapLines {
    public static let waitingForPairing = "waiting for iOS pairing"

    /// ATT insufficient authentication or encryption. The domain check keeps a
    /// localized sentence from deciding.
    public static func isEncryptionRefusal(domain: String, code: Int) -> Bool {
        domain == "CBATTErrorDomain" && (code == 5 || code == 15)
    }

    /// `domain` and `code` are nil when CoreBluetooth reports no error, which
    /// is what a local `cancelPeripheralConnection` produces.
    public static func disconnected(domain: String?, code: Int?, millisecondsSinceConnect: Int?, localCancel: Bool) -> String {
        let codeText = code.map(String.init) ?? "none"
        let since = millisecondsSinceConnect.map { "\($0)ms since connect" } ?? "no connect time"
        let who = localCancel ? "local cancel" : "not our cancel"
        return "disconnected: domain \(domain ?? "none") code \(codeText) \(since) \(who)"
    }
}
