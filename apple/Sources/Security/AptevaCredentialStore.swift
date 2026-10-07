import Foundation
import Security

public struct AptevaStoredCredential: Codable, Equatable, Sendable {
    public let serverURL: String
    public let email: String
    public let apiKey: String
    public let keyID: Int64

    public init(serverURL: String, email: String, apiKey: String, keyID: Int64) {
        self.serverURL = serverURL
        self.email = email
        self.apiKey = apiKey
        self.keyID = keyID
    }

    public var account: String {
        Self.account(serverURL: serverURL, email: email)
    }

    public static func account(serverURL: String, email: String) -> String {
        "\(serverURL.lowercased())|\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }
}

public enum AptevaCredentialStoreError: LocalizedError {
    case encoding
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encoding:
            "The secure credential could not be encoded."
        case let .keychain(status):
            "The secure credential could not be saved (\(status))."
        }
    }
}

public struct AptevaCredentialStore: Sendable {
    private let service: String

    /// The default preserves credentials created by the original iPhone app.
    /// New standalone apps may provide their own stable service identifier.
    public init(service: String = "com.apteva.ios.instance-credentials") {
        self.service = service
    }

    public func load(serverURL: String, email: String) throws -> AptevaStoredCredential? {
        let account = AptevaStoredCredential.account(serverURL: serverURL, email: email)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AptevaCredentialStoreError.keychain(status)
        }
        guard let data = result as? Data,
              let credential = try? JSONDecoder().decode(AptevaStoredCredential.self, from: data) else {
            throw AptevaCredentialStoreError.encoding
        }
        return credential
    }

    public func save(_ credential: AptevaStoredCredential) throws {
        guard let data = try? JSONEncoder().encode(credential) else {
            throw AptevaCredentialStoreError.encoding
        }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credential.account,
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(identity as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AptevaCredentialStoreError.keychain(updateStatus)
        }

        var insertion = identity
        values.forEach { insertion[$0.key] = $0.value }
        let addStatus = SecItemAdd(insertion as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AptevaCredentialStoreError.keychain(addStatus)
        }
    }

    public func delete(serverURL: String, email: String) throws {
        let account = AptevaStoredCredential.account(serverURL: serverURL, email: email)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AptevaCredentialStoreError.keychain(status)
        }
    }
}
