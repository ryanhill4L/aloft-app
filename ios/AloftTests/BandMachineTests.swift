import XCTest
@testable import Aloft

final class BandMachineTests: XCTestCase {
    private let strap = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testFindWithNoMemoryScans() {
        var machine = BandMachine()
        let outcome = machine.send(.find)
        XCTAssertEqual(machine.state, .scanning)
        XCTAssertTrue(outcome.scan)
        XCTAssertFalse(outcome.connect)
        XCTAssertEqual(outcome.log, "idle → scanning")
    }

    func testFindRetrievesTheRememberedStrapBeforeScanning() {
        var machine = BandMachine()
        machine.remembered = strap
        let outcome = machine.send(.find)
        XCTAssertEqual(machine.state, .connecting)
        XCTAssertTrue(outcome.retrieve)
        XCTAssertFalse(outcome.scan)

        let missed = machine.send(.retrieved(false))
        XCTAssertEqual(machine.state, .scanning)
        XCTAssertTrue(missed.scan)

        let found = machine.send(.discovered(strap))
        XCTAssertEqual(machine.state, .connecting)
        XCTAssertTrue(found.connect)
        XCTAssertTrue(found.stopScan)
    }

    func testDiscoveryConnectsTheFirstStrapAndIgnoresTheRest() {
        var machine = BandMachine()
        _ = machine.send(.find)
        let other = UUID()
        let first = machine.send(.discovered(strap))
        XCTAssertTrue(first.connect)
        XCTAssertEqual(machine.remembered, strap)
        let ignored = machine.send(.discovered(other))
        XCTAssertFalse(ignored.connect)
        XCTAssertEqual(machine.remembered, strap)
        XCTAssertEqual(machine.state, .connecting)
    }

    func testScanIgnoresAStrapThatIsNotTheRememberedOne() {
        var machine = BandMachine()
        machine.remembered = strap
        _ = machine.send(.find)
        _ = machine.send(.retrieved(false))
        let other = machine.send(.discovered(UUID()))
        XCTAssertFalse(other.connect)
        XCTAssertEqual(machine.state, .scanning)
        XCTAssertEqual(machine.remembered, strap)
    }

    func testHelloSuccessMarksReadyAndARefusalRetriesOnceThenStops() {
        var machine = BandMachine()
        _ = machine.send(.find)
        _ = machine.send(.discovered(strap))
        _ = machine.send(.connected)
        XCTAssertEqual(machine.state, .pairing)

        let ready = machine.send(.paired)
        XCTAssertEqual(machine.state, .ready)
        XCTAssertTrue(ready.subscribe)
        XCTAssertTrue(machine.canCommand)

        var pairing = reachPairing()
        let first = pairing.send(.authRefused)
        XCTAssertEqual(pairing.state, .pairing)
        XCTAssertTrue(pairing.waitingForPairing)
        XCTAssertFalse(first.cancel)
        XCTAssertFalse(pairing.expectingDrop)
        XCTAssertEqual(first.schedulePairWait, BandMachine.pairingPromptSeconds)
        XCTAssertEqual(BandMachine.pairingPromptSeconds, 30)
        XCTAssertTrue(first.awaitingPairing)
        XCTAssertTrue(pairing.statusLine.contains("Waiting for iOS pairing"))

        let second = pairing.send(.authRefused)
        XCTAssertFalse(second.cancel)
        XCTAssertNil(second.schedulePairWait)
        XCTAssertEqual(pairing.state, .pairing)

        let retry = pairing.send(.encryptionUp)
        XCTAssertTrue(retry.retryHello)
        XCTAssertEqual(pairing.state, .pairing)
        let ignored = pairing.send(.encryptionUp)
        XCTAssertFalse(ignored.retryHello)

        let readyAfter = pairing.send(.paired)
        XCTAssertEqual(pairing.state, .ready)
        XCTAssertTrue(readyAfter.subscribe)

        var timed = reachPairing()
        _ = timed.send(.authRefused)
        let done = timed.send(.pairWaitElapsed)
        XCTAssertEqual(timed.state, .failed(BandMachine.pairingFailed))
        XCTAssertTrue(done.cancel)
        XCTAssertTrue(timed.expectingDrop)
        XCTAssertFalse(timed.statusLine.contains("WHOOP app"))
        XCTAssertTrue(BandMachine.pairingFailed.contains("flash blue"))
    }

    func testAuthenticationAfterTheRetryShowsTheOffWristSteps() {
        var pairing = reachPairing()
        let first = pairing.send(.authRefused)
        XCTAssertEqual(first.schedulePairWait, BandMachine.pairingPromptSeconds)
        XCTAssertFalse(first.cancel)
        XCTAssertTrue(pairing.send(.encryptionUp).retryHello)
        let refused = pairing.send(.offWrist)
        XCTAssertEqual(pairing.state, .failed(BandMachine.offWrist))
        XCTAssertTrue(refused.cancel)
        XCTAssertFalse(refused.connect)
        XCTAssertNil(refused.schedulePairWait)
        XCTAssertTrue(pairing.statusLine.contains("off your wrist"))
        XCTAssertTrue(pairing.statusLine.contains("underside lights"))
        XCTAssertTrue(pairing.statusLine.contains("two fingers"))
        XCTAssertTrue(pairing.statusLine.contains("only blue"))
        XCTAssertFalse(pairing.statusLine.contains("Reset All Settings"))
        XCTAssertFalse(pairing.statusLine.contains("old Bluetooth bond"))
    }

    func testDropDuringThePromptWaitDoesNotReconnect() {
        var pairing = reachPairing()
        _ = pairing.send(.authRefused)
        let drop = pairing.send(.linkDropped)
        XCTAssertEqual(pairing.state, .failed(BandMachine.pairingFailed))
        XCTAssertFalse(drop.connect)
        XCTAssertNil(drop.schedulePairWait)
        XCTAssertNil(drop.scheduleBackoff)
    }

    func testDropBeforeHelloRetriesTheLinkOnce() {
        var pairing = reachPairing()
        let drop = pairing.send(.linkDropped)
        XCTAssertTrue(drop.cancel)
        XCTAssertEqual(drop.schedulePairWait, BandMachine.pairWaitSeconds)
        XCTAssertEqual(pairing.state, .pairing)
        XCTAssertFalse(pairing.waitingForPairing)

        let echo = pairing.send(.linkDropped)
        XCTAssertFalse(echo.cancel)
        XCTAssertEqual(pairing.state, .pairing)

        let again = pairing.send(.pairWaitElapsed)
        XCTAssertTrue(again.connect)
        _ = pairing.send(.connected)
        let refused = pairing.send(.authRefused)
        XCTAssertEqual(pairing.state, .pairing)
        XCTAssertFalse(refused.cancel)
        XCTAssertTrue(pairing.waitingForPairing)
    }

    func testUnexpectedConnectIsCancelled() {
        var machine = BandMachine()
        let outcome = machine.send(.connected)
        XCTAssertTrue(outcome.cancel)
        XCTAssertEqual(machine.state, .idle)
    }

    func testReadyDropBacksOffThenStops() {
        var machine = paired()
        var delays: [Int] = []
        for expected in BandMachine.backoffSeconds {
            let drop = machine.send(.linkDropped)
            XCTAssertEqual(drop.scheduleBackoff, expected)
            XCTAssertEqual(machine.state, .connecting)
            XCTAssertEqual(machine.waitSeconds, expected)
            delays.append(expected)
            let due = machine.send(.backoffElapsed)
            XCTAssertTrue(due.connect)
            _ = machine.send(.connected)
            _ = machine.send(.paired)
        }
        XCTAssertEqual(delays, [2, 5, 15, 60])
        let done = machine.send(.linkDropped)
        XCTAssertNil(done.scheduleBackoff)
        XCTAssertEqual(machine.state, .failed(BandMachine.dropped))
    }

    func testDisconnectKeepsTheMemoryAndForgetClearsIt() {
        var machine = paired()
        let disconnect = machine.send(.disconnect)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(machine.remembered, strap)
        XCTAssertFalse(disconnect.clearMemory)
        XCTAssertFalse(machine.wantsLink)

        _ = machine.send(.find)
        let forget = machine.send(.forget)
        XCTAssertNil(machine.remembered)
        XCTAssertTrue(forget.clearMemory)
        XCTAssertEqual(machine.state, .idle)
    }

    func testBluetoothOffAndOnResumesAWantedLink() {
        var machine = paired()
        _ = machine.send(.poweredOff)
        XCTAssertEqual(machine.state, .off)
        let back = machine.send(.poweredOn)
        XCTAssertTrue(back.retrieve)
        XCTAssertEqual(machine.state, .connecting)
    }

    func testBluetoothOffAndOnStaysIdleWhenNothingWasAsked() {
        var machine = BandMachine()
        _ = machine.send(.poweredOff)
        let back = machine.send(.poweredOn)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(back.scan)
    }

    func testPairingRefusalIsTheAttCodesNotTheSentence() {
        XCTAssertTrue(BandMachine.isPairingRefusal(domain: "CBATTErrorDomain", code: 5))
        XCTAssertTrue(BandMachine.isPairingRefusal(domain: "CBATTErrorDomain", code: 15))
        XCTAssertFalse(BandMachine.isPairingRefusal(domain: "CBATTErrorDomain", code: 1))
        XCTAssertFalse(BandMachine.isPairingRefusal(domain: "CBErrorDomain", code: 5))
    }

    private func reachPairing() -> BandMachine {
        var machine = BandMachine()
        _ = machine.send(.find)
        _ = machine.send(.discovered(strap))
        _ = machine.send(.connected)
        return machine
    }

    private func paired() -> BandMachine {
        var machine = BandMachine()
        _ = machine.send(.find)
        _ = machine.send(.discovered(strap))
        _ = machine.send(.connected)
        _ = machine.send(.paired)
        return machine
    }
}
