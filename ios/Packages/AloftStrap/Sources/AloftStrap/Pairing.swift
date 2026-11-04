/// Lines and ATT checks for the 5/MG bond. CoreBluetooth stays in the app.
///
/// A confirmed write that comes back as insufficient encryption (15) is what
/// makes iOS start pairing. Cancelling on that first error aborts the prompt.
/// Authentication insufficient (5) after the hello was retried means the link
/// had encrypted and the strap still refused the command.
public enum StrapLines {
    public static let waitingForPairing = "waiting for iOS pairing"
    /// The hello retry came back ATT 5 after this link had already asked for
    /// encryption. Factual log line, not a guess about why.
    public static let encryptedButRefused = "hello refused authentication after the link encrypted, no prompt"

    /// ATT insufficient authentication or encryption. The domain check keeps a
    /// localized sentence from deciding.
    public static func isEncryptionRefusal(domain: String, code: Int) -> Bool {
        domain == "CBATTErrorDomain" && (code == 5 || code == 15)
    }

    /// True only when the link was held, the hello was sent again, and that
    /// retry came back authentication-insufficient (5). Another 15 means the
    /// link is still not encrypted, so the first wait continues.
    public static func refusedAfterEncrypt(waiting: Bool, retriedHello: Bool, code: Int) -> Bool {
        waiting && retriedHello && code == 5
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
