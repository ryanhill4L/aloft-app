import Foundation

/// Who connects, when pairing may be tried again, and when a drop backs off.
/// CoreBluetooth lives in `StrapLink`. This is only the decisions, so the
/// retry rules can be tested without a radio.
struct BandMachine: Equatable {
    enum State: Equatable, CustomStringConvertible {
        case idle
        case scanning
        case connecting
        case pairing
        case ready
        case failed(String)
        case off

        var description: String {
            switch self {
            case .idle: "idle"
            case .scanning: "scanning"
            case .connecting: "connecting"
            case .pairing: "pairing"
            case .ready: "ready"
            case .failed(let reason): "failed(\(reason))"
            case .off: "off"
            }
        }

        /// Short label for the Log row.
        var name: String {
            switch self {
            case .idle: "Idle"
            case .scanning: "Scanning"
            case .connecting: "Connecting"
            case .pairing: "Pairing"
            case .ready: "Ready"
            case .failed: "Failed"
            case .off: "Bluetooth off"
            }
        }
    }

    enum Event: Equatable {
        case poweredOn
        case poweredOff
        case notAllowed
        case find
        case retry
        case retrieved(Bool)
        case discovered(UUID)
        case choose(UUID)
        case connected
        case paired
        case authRefused
        case linkDropped
        case pairWaitElapsed
        case backoffElapsed
        case disconnect
        case forget
    }

    struct Outcome: Equatable {
        var log: String = ""
        var scan = false
        var stopScan = false
        var retrieve = false
        var connect = false
        var cancel = false
        var clearMemory = false
        var subscribe = false
        var schedulePairWait = false
        var scheduleBackoff: Int?
        var cancelTimers = false
    }

    /// After a ready link drops. One attempt at each delay, then stop.
    static let backoffSeconds = [2, 5, 15, 60]
    /// Time for the iOS pairing prompt before the single retry.
    static let pairWaitSeconds = 12

    static let pairingFailed = "Pairing didn't finish. Keep the strap close, accept the iOS prompt, then tap Retry."
    static let dropped = "The strap dropped. Tap Retry."
    static let notAllowed = "Bluetooth isn't allowed. Allow it in Settings, then tap Retry."

    /// ATT codes that mean the link is not encrypted yet. 5 is authentication,
    /// 15 is encryption. Locale-independent, unlike the error string.
    static func isPairingRefusal(domain: String, code: Int) -> Bool {
        domain == "CBATTErrorDomain" && (code == 5 || code == 15)
    }

    var state: State = .idle
    var remembered: UUID?
    /// Find was asked, and Disconnect or Forget has not cancelled it.
    var wantsLink = false
    var pairingAttempts = 0
    var drops = 0
    /// The next link-dropped callback is one we caused by cancelling.
    var expectingDrop = false
    var waitSeconds: Int?

    var canCommand: Bool { state == .ready }

    var statusLine: String {
        switch state {
        case .idle:
            "Idle. Tap Find to look for the strap."
        case .scanning:
            "Scanning. Keep the strap close."
        case .connecting:
            if let waitSeconds { "Connecting in \(waitSeconds)s." } else { "Connecting." }
        case .pairing:
            pairingAttempts == 0
                ? "Pairing. Accept the iOS prompt if it appears."
                : "Pairing. Waiting for the iOS prompt, then trying once more."
        case .ready:
            "Ready. The strap can take commands."
        case .failed(let reason):
            reason
        case .off:
            "Bluetooth is off. Turn it on, then tap Find."
        }
    }

    mutating func send(_ event: Event) -> Outcome {
        let before = state
        var outcome = Outcome()
        switch event {
        case .poweredOff:
            outcome.cancelTimers = true
            outcome.cancel = true
            outcome.stopScan = true
            state = .off
        case .notAllowed:
            outcome.cancelTimers = true
            outcome.cancel = true
            outcome.stopScan = true
            wantsLink = false
            state = .failed(Self.notAllowed)
        case .poweredOn:
            guard state == .off else { break }
            if wantsLink { return send(.find) }
            state = .idle
        case .find, .retry:
            startFind(&outcome)
        case .retrieved(let found):
            guard state == .connecting else { break }
            if found {
                waitSeconds = nil
                outcome.connect = true
            } else {
                state = .scanning
                outcome.scan = true
            }
        case .discovered(let id):
            guard state == .scanning else { break }
            if let remembered, remembered != id { break }
            remembered = id
            state = .connecting
            outcome.stopScan = true
            outcome.connect = true
        case .choose(let id):
            remembered = id
            wantsLink = true
            pairingAttempts = 0
            drops = 0
            expectingDrop = false
            waitSeconds = nil
            outcome.cancelTimers = true
            outcome.stopScan = true
            state = .connecting
            outcome.connect = true
        case .connected:
            switch state {
            case .connecting, .pairing:
                state = .pairing
                waitSeconds = nil
                outcome.cancelTimers = true
            default:
                // A connect we did not ask for. Cancelling is what stops the
                // system from retrying the link on its own.
                outcome.cancel = true
                expectingDrop = true
            }
        case .paired:
            guard state == .pairing else { break }
            pairingAttempts = 0
            waitSeconds = nil
            state = .ready
            outcome.subscribe = true
            outcome.cancelTimers = true
        case .authRefused:
            refuse(&outcome)
        case .pairWaitElapsed:
            guard state == .pairing, pairingAttempts == 1, remembered != nil else { break }
            waitSeconds = nil
            expectingDrop = false
            state = .connecting
            outcome.connect = true
        case .linkDropped:
            if expectingDrop || waitSeconds != nil {
                expectingDrop = false
                break
            }
            outcome.cancel = true
            expectingDrop = true
            outcome.cancelTimers = true
            switch state {
            case .ready:
                if drops >= Self.backoffSeconds.count {
                    state = .failed(Self.dropped)
                } else {
                    let seconds = Self.backoffSeconds[drops]
                    drops += 1
                    waitSeconds = seconds
                    state = .connecting
                    outcome.scheduleBackoff = seconds
                }
            case .connecting where drops > 0:
                if drops >= Self.backoffSeconds.count {
                    state = .failed(Self.dropped)
                } else {
                    let seconds = Self.backoffSeconds[drops]
                    drops += 1
                    waitSeconds = seconds
                    state = .connecting
                    outcome.scheduleBackoff = seconds
                }
            case .connecting, .pairing:
                refuse(&outcome)
            default:
                break
            }
        case .backoffElapsed:
            guard state == .connecting else { break }
            waitSeconds = nil
            expectingDrop = false
            outcome.connect = true
        case .disconnect:
            wantsLink = false
            expectingDrop = true
            waitSeconds = nil
            outcome.cancel = true
            outcome.stopScan = true
            outcome.cancelTimers = true
            state = .idle
        case .forget:
            wantsLink = false
            expectingDrop = true
            remembered = nil
            waitSeconds = nil
            outcome.cancel = true
            outcome.stopScan = true
            outcome.cancelTimers = true
            outcome.clearMemory = true
            state = .idle
        }
        outcome.log = "\(before) → \(state)"
        return outcome
    }

    private mutating func startFind(_ outcome: inout Outcome) {
        wantsLink = true
        pairingAttempts = 0
        drops = 0
        expectingDrop = false
        waitSeconds = nil
        outcome.cancelTimers = true
        if remembered != nil {
            state = .connecting
            outcome.retrieve = true
            outcome.stopScan = true
        } else {
            state = .scanning
            outcome.scan = true
        }
    }

    /// One wait, then one more try. A second refusal stops. Cancelling the
    /// link is required: CoreBluetooth otherwise reconnects on its own.
    private mutating func refuse(_ outcome: inout Outcome) {
        outcome.cancel = true
        outcome.cancelTimers = true
        expectingDrop = true
        if pairingAttempts == 0 {
            pairingAttempts = 1
            waitSeconds = Self.pairWaitSeconds
            state = .pairing
            outcome.schedulePairWait = true
        } else {
            waitSeconds = nil
            state = .failed(Self.pairingFailed)
        }
    }
}
