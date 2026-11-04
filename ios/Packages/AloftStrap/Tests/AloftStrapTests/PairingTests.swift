import Testing
@testable import AloftStrap

@Suite struct PairingTests {
    @Test func encryptionRefusalIsTheAttCodes() {
        #expect(StrapLines.isEncryptionRefusal(domain: "CBATTErrorDomain", code: 5))
        #expect(StrapLines.isEncryptionRefusal(domain: "CBATTErrorDomain", code: 15))
        #expect(!StrapLines.isEncryptionRefusal(domain: "CBATTErrorDomain", code: 1))
        #expect(!StrapLines.isEncryptionRefusal(domain: "CBErrorDomain", code: 15))
    }

    @Test func disconnectLineNamesTheDomainCodeAndWhoHungUp() {
        #expect(
            StrapLines.disconnected(domain: nil, code: nil, millisecondsSinceConnect: 8, localCancel: true)
                == "disconnected: domain none code none 8ms since connect local cancel"
        )
        #expect(
            StrapLines.disconnected(domain: "CBErrorDomain", code: 7, millisecondsSinceConnect: 1200, localCancel: false)
                == "disconnected: domain CBErrorDomain code 7 1200ms since connect not our cancel"
        )
        #expect(StrapLines.disconnected(domain: nil, code: nil, millisecondsSinceConnect: nil, localCancel: false).contains("no connect time"))
        #expect(StrapLines.waitingForPairing == "waiting for iOS pairing")
    }

    @Test func storedBondIsAuthenticationAfterTheRetry() {
        #expect(StrapLines.storedBondRefused(waiting: true, retriedHello: true, code: 5))
        #expect(!StrapLines.storedBondRefused(waiting: true, retriedHello: true, code: 15))
        #expect(!StrapLines.storedBondRefused(waiting: true, retriedHello: false, code: 5))
        #expect(!StrapLines.storedBondRefused(waiting: false, retriedHello: true, code: 5))
        #expect(StrapLines.encryptedButRefused.contains("no prompt"))
    }
}
