import Foundation
import CoreFoundation

/// A push carries an opaque server notification ID, not a conversation message ID.
public struct AptevaPushDestination: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let kind: String
    public let itemID: Int64
    public let projectID: String?
    public let instanceRef: String?

    public init?(userInfo: [AnyHashable: Any]) {
        let data = userInfo["data"] as? [AnyHashable: Any] ?? [:]
        func value(_ key: String) -> Any? { userInfo[key] ?? data[key] }
        guard let kind = (value("type") as? String)?.lowercased(),
              ["notification", "approval", "report", "alert"].contains(kind) else { return nil }
        let number = value("item_id") as? NSNumber
        let rawID = (value("item_id") as? String)
            ?? number.flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.stringValue }
        guard let rawID, let itemID = Int64(rawID), itemID > 0 else { return nil }
        self.kind = kind
        self.itemID = itemID
        projectID = (value("project_id") as? String).flatMap { $0.isEmpty ? nil : $0 }
        instanceRef = (value("instance_ref") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct AptevaNotificationChannels: Codable, Hashable, Sendable {
    public let inApp: Bool
    public let tab: Bool
    public let desktop: Bool
    public let mobile: Bool
    enum CodingKeys: String, CodingKey { case inApp = "in_app", tab, desktop, mobile }
}

public struct AptevaUserNotification: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let installID: Int64
    public let projectID: String
    public let type: String
    public let app: String
    public let title: String
    public let body: String
    public let url: String
    public let group: String
    public let read: Bool
    public let channels: AptevaNotificationChannels
    enum CodingKeys: String, CodingKey {
        case id, type, app, title, body, url, group, read, channels
        case installID = "install_id", projectID = "project_id"
    }

    /// Validate server-returned routing before selecting a native app/project.
    /// Never navigate or forward credentials to an arbitrary URL from a push.
    public func link(baseURL: URL) throws -> AptevaNotificationLink {
        guard id > 0, installID > 0,
              let resolved = URL(string: url, relativeTo: baseURL)?.absoluteURL,
              resolved.scheme == baseURL.scheme, resolved.host == baseURL.host,
              resolved.port == baseURL.port, resolved.user == nil, resolved.password == nil,
              resolved.fragment == nil,
              let components = URLComponents(url: resolved, resolvingAgainstBaseURL: true),
              components.path == "/apps/\(app)/page" else { throw AptevaAPIError.invalidResponse }
        let items = components.queryItems ?? []
        guard Set(items.map(\.name)).count == items.count else { throw AptevaAPIError.invalidResponse }
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard query["install_id"] == String(installID), query["project_id"] == projectID else {
            throw AptevaAPIError.invalidResponse
        }
        let messageID: String?
        if let raw = query["message_id"] {
            guard let id = Int64(raw), id > 0 else { throw AptevaAPIError.invalidResponse }
            messageID = String(id)
        } else { messageID = nil }
        return AptevaNotificationLink(conversationID: query["chat"].flatMap { $0.isEmpty ? nil : $0 }, messageID: messageID)
    }
}

public struct AptevaNotificationLink: Hashable, Sendable {
    public let conversationID: String?
    public let messageID: String?
}

public struct AptevaNotificationSnapshot: Decodable, Sendable {
    public let items: [AptevaUserNotification]
    public let unreadCount: Int
    public let tabCount: Int
    public let nextBefore: Int64
    enum CodingKeys: String, CodingKey {
        case items, unreadCount = "unread_count", tabCount = "tab_count", nextBefore = "next_before"
    }
}

struct NotificationAcknowledgement: Decodable, Sendable { let ok: Bool }

/// Selection data is fetched with the authenticated app API before presentation.
public struct NativeChatDeepLink: Hashable, Sendable {
    public let conversationID: String
    public let conversation: NativeJSONValue
    public let messageID: String?
    public init(conversationID: String, conversation: NativeJSONValue, messageID: String? = nil) {
        self.conversationID = conversationID
        self.conversation = conversation
        self.messageID = messageID
    }
}
