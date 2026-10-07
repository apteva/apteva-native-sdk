import Foundation
import XCTest
@testable import AptevaNativeSDK

final class CredentialStoreTests: XCTestCase {
    func testCredentialRoundTripAndDeletion() throws {
        let store = AptevaCredentialStore()
        let suffix = UUID().uuidString.lowercased()
        let credential = AptevaStoredCredential(
            serverURL: "https://\(suffix).example.test",
            email: "\(suffix)@example.test",
            apiKey: "sk-test-\(suffix)",
            keyID: 42
        )
        defer {
            try? store.delete(
                serverURL: credential.serverURL,
                email: credential.email
            )
        }

        try store.save(credential)
        XCTAssertEqual(
            try store.load(serverURL: credential.serverURL, email: credential.email),
            credential
        )

        try store.delete(serverURL: credential.serverURL, email: credential.email)
        XCTAssertNil(
            try store.load(serverURL: credential.serverURL, email: credential.email)
        )
    }

    func testCredentialAccountIsCaseInsensitive() {
        XCTAssertEqual(
            AptevaStoredCredential.account(
                serverURL: "https://EXAMPLE.TEST",
                email: " User@Example.Test "
            ),
            "https://example.test|user@example.test"
        )
    }
}
