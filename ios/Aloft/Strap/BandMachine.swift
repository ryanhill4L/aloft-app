import AloftStrap
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
        case encryptionUp
        case offWrist
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
        /// Seconds to stay in pairing before the next decision. Nil means don't arm one.
        var schedulePairWait: Int?
        var awaitingPairing = false
        var retryHello = false
        var scheduleBackoff: Int?
        var cancelTimers = false
    }

    /// After a ready link drops. One attempt at each delay, then stop.
    static let backoffSeconds = [2, 5, 15, 60]
    /// After a drop we did not ask for, before one reconnect.
    static let pairWaitSeconds = 12
    /// How long to hold the link after ATT 5 or 15 so iOS can show pairing.
    /// Cancelling here is what aborts the prompt.
    static let pairingPromptSeconds = 30
    /// Gap before reading the battery characteristic, which a 5/MG refuses until the link is encrypted.
    static let encryptionProbeSeconds = 5

    static let pairingFailed = "Pairing didn't finish. Tap the band until the LEDs flash blue, then tap Retry."
    /// ATT 5 after the link encrypted. The off-wrist taps are what put this strap
    /// into pairing mode; tapping it while worn did not light the side blue.
    static let offWrist = "Take the strap off your wrist and wait until the underside lights are off. Hold it by the sides and tap the top of the sensor firmly with two fingers until the side light is only blue. Then tap Retry."
    static let dropped = "The strap dropped. Tap Retry."
    static let notAllowed = "Bluetooth isn't allowed. Allow it in Settings, then tap Retry."

    /// ATT codes that mean the link is not encrypted yet. 5 is authentication,
    /// 15 is encryption. Locale-independent, unlike the error string.
    static func isPairingRefusal(domain: String, code: Int) -> Bool {
        StrapLines.isEncryptionRefusal(domain: domain, code: code)
    }

    var state: State = .idle
    var remembered: UUID?
    /// Find was asked, and Disconnect or Forget has not cancelled it.
    var wantsLink = false
    var pairingAttempts = 0
    /// ATT 5 or 15 arrived, and the link is being held for the iOS prompt.
    var waitingForPairing = false
    /// The hello (or WHOOP 4 bond write) has been sent again after encryption came up.
    var helloRetried = false
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
            waitingForPairing
                ? "Waiting for iOS pairing. Keep the strap close."
                : "Pairing."
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
            clearPairingWait()
            outcome.cancelTimers = true
            outcome.stopScan = true
            state = .connecting
            outcome.connect = true
        case .connected:
            switch state {
            case .connecting, .pairing:
                state = .pairing
                clearPairingWait()
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
            clearPairingWait()
            state = .ready
            outcome.subscribe = true
            outcome.cancelTimers = true
        case .authRefused:
            guard state == .pairing else { break }
            // Another 5 or 15 while the prompt wait is already running must not
            // cancel the link. That cancel is what aborts iOS pairing.
            if waitingForPairing { break }
            waitingForPairing = true
            helloRetried = false
            waitSeconds = Self.pairingPromptSeconds
            outcome.schedulePairWait = Self.pairingPromptSeconds
            outcome.awaitingPairing = true
        case .encryptionUp:
            guard state == .pairing, waitingForPairing, !helloRetried else { break }
            helloRetried = true
            outcome.retryHello = true
        case .offWrist:
            // The retried hello got ATT 5. The first ATT 15 already held the
            // link; staying longer does not show the steps that put the strap
            // in pairing mode. Let go so those taps can.
            guard state == .pairing, waitingForPairing, helloRetried else { break }
            outcome.cancel = true
            outcome.cancelTimers = true
            expectingDrop = true
            clearPairingWait()
            state = .failed(Self.offWrist)
        case .pairWaitElapsed:
            if waitingForPairing {
                guard state == .pairing else { break }
                outcome.cancel = true
                outcome.cancelTimers = true
                expectingDrop = true
                clearPairingWait()
                state = .failed(Self.pairingFailed)
                break
            }
            guard state == .pairing, pairingAttempts == 1, remembered != nil else { break }
            waitSeconds = nil
            expectingDrop = false
            state = .connecting
            outcome.connect = true
        case .linkDropped:
            if state == .pairing, waitingForPairing, !expectingDrop {
                // The strap left during the prompt wait. Reconnecting would
                // hammer a bond it is refusing. The log already has the error.
                outcome.cancel = true
                outcome.cancelTimers = true
                expectingDrop = true
                clearPairingWait()
                state = .failed(Self.pairingFailed)
                break
            }
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
            clearPairingWait()
            outcome.cancel = true
            outcome.stopScan = true
            outcome.cancelTimers = true
            state = .idle
        case .forget:
            wantsLink = false
            expectingDrop = true
            remembered = nil
            clearPairingWait()
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
        clearPairingWait()
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

    /// A drop before any ATT refusal: cancel so CoreBluetooth does not reconnect
    /// on its own, wait, then try the link once more. A second drop stops.
    /// An encryption refusal does not come through here. That path holds the link.
    private mutating func refuse(_ outcome: inout Outcome) {
        outcome.cancel = true
        outcome.cancelTimers = true
        expectingDrop = true
        if pairingAttempts == 0 {
            pairingAttempts = 1
            waitSeconds = Self.pairWaitSeconds
            state = .pairing
            outcome.schedulePairWait = Self.pairWaitSeconds
        } else {
            waitSeconds = nil
            state = .failed(Self.pairingFailed)
        }
    }

    private mutating func clearPairingWait() {
        waitingForPairing = false
        helloRetried = false
        waitSeconds = nil
    }
}
