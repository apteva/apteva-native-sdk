import Foundation

public struct AptevaMobilePushConfig: Decodable, Sendable {
    public let enabled: Bool
    public let supportsBackgroundRefresh: Bool

    public enum CodingKeys: String, CodingKey {
        case enabled
        case supportsBackgroundRefresh = "supports_background_refresh"
    }
}

public struct AptevaMobilePushSubscription: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let installationID: String
    public let relayDeviceID: String
    public let grantExpiresAt: String
    public let bundleID: String
    public let environment: String
    public let appVersion: String?
    public let deviceName: String?
    public let status: String
    public let lastBadge: Int
    public let lastError: String?

    public enum CodingKeys: String, CodingKey {
        case id, environment, status
        case installationID = "installation_id"
        case relayDeviceID = "relay_device_id"
        case grantExpiresAt = "grant_expires_at"
        case bundleID = "bundle_id"
        case appVersion = "app_version"
        case deviceName = "device_name"
        case lastBadge = "last_badge"
        case lastError = "last_error"
    }
}

public struct AptevaMobilePushSubscriptionsResponse: Decodable, Sendable {
    public let subscriptions: [AptevaMobilePushSubscription]
}

public struct AptevaMobilePushSubscriptionResponse: Decodable, Sendable {
    public let subscription: AptevaMobilePushSubscription
}

public struct AptevaMobilePushDeleteResponse: Decodable, Sendable {
    public let deleted: Bool
    public let remoteRevoked: Bool

    public enum CodingKeys: String, CodingKey {
        case deleted
        case remoteRevoked = "remote_revoked"
    }
}

public struct AptevaMobilePushTestResponse: Decodable, Sendable {
    public let delivery: AptevaMobilePushDelivery
}

public struct AptevaMobilePushDelivery: Decodable, Sendable {
    public let id: String?
    public let status: String?
}
