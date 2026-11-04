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

        var pairing = BandMachine()
        _ = pairing.send(.find)
        _ = pairing.send(.discovered(strap))
        _ = pairing.send(.connected)
        let first = pairing.send(.authRefused)
        XCTAssertEqual(pairing.state, .pairing)
        XCTAssertEqual(pairing.pairingAttempts, 1)
        XCTAssertTrue(first.cancel)
        XCTAssertTrue(first.schedulePairWait)
        XCTAssertTrue(pairing.expectingDrop)

        let echo = pairing.send(.linkDropped)
        XCTAssertFalse(echo.cancel)
        XCTAssertEqual(pairing.state, .pairing)

        let again = pairing.send(.pairWaitElapsed)
        XCTAssertEqual(again.connect, true)
        _ = pairing.send(.connected)
        let second = pairing.send(.authRefused)
        XCTAssertEqual(pairing.state, .failed(BandMachine.pairingFailed))
        XCTAssertFalse(second.schedulePairWait)
        XCTAssertFalse(pairing.statusLine.contains("WHOOP app"))
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

    private func paired() -> BandMachine {
        var machine = BandMachine()
        _ = machine.send(.find)
        _ = machine.send(.discovered(strap))
        _ = machine.send(.connected)
        _ = machine.send(.paired)
        return machine
    }
}
