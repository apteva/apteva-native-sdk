import Foundation

public struct AptevaCurrentStatus: Decodable, Identifiable, Sendable {
    public let message: AptevaChatMessage
    public let instanceID: Int64
    public let instanceName: String
    public let projectID: String
    public let updatedAt: String?
    public let title: String
    public let detail: String?
    public let state: String
    public let progress: Double?
    public let next: String?
    public let nextAt: String?
    public let stale: Bool

    public var id: Int64 { instanceID }
    public var updatedDate: Date {
        parseAptevaDate(updatedAt ?? message.createdAt) ?? .distantPast
    }

    public enum CodingKeys: String, CodingKey {
        case message, title, detail, state, progress, next, stale
        case instanceID = "instance_id"
        case instanceName = "instance_name"
        case projectID = "project_id"
        case updatedAt = "updated_at"
        case nextAt = "next_at"
    }
}

public struct AptevaConversation: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let instanceID: Int64
    public let agentIDs: [Int64]
    public let projectID: String
    public let kind: String
    public let title: String
    public let createdAt: String
    public let updatedAt: String
    public let archivedAt: String?
    public let threadID: String?

    public init(id: String, instanceID: Int64, agentIDs: [Int64], projectID: String, kind: String, title: String, createdAt: String, updatedAt: String, archivedAt: String?, threadID: String?) {
        self.id = id
        self.instanceID = instanceID
        self.agentIDs = agentIDs
        self.projectID = projectID
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.threadID = threadID
    }

    public enum CodingKeys: String, CodingKey {
        case id, kind, title
        case instanceID = "instance_id"
        case agentIDs = "agent_ids"
        case projectID = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case archivedAt = "archived_at"
        case threadID = "thread_id"
    }
}

public struct AptevaConversationAttachment: Codable, Identifiable, Sendable {
    public let id: String?
    public let type: String
    public let dataURL: String?
    public let name: String?
    public let mimeType: String?
    public let size: Int?
    public let ephemeral: Bool?

    public init(id: String?, type: String, dataURL: String?, name: String?, mimeType: String?, size: Int?, ephemeral: Bool?) {
        self.id = id
        self.type = type
        self.dataURL = dataURL
        self.name = name
        self.mimeType = mimeType
        self.size = size
        self.ephemeral = ephemeral
    }

    public enum CodingKeys: String, CodingKey {
        case id, type, name, size, ephemeral
        case dataURL = "data_url"
        case mimeType = "mime_type"
    }
}

public struct AptevaConversationMessage: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let chatID: String
    public let role: String
    public let content: String
    public let userID: Int64?
    public let agentID: Int64?
    public let threadID: String?
    public let status: String
    public let createdAt: String
    public let components: [AptevaChatComponent]?
    public let attachments: [AptevaConversationAttachment]?
    public let metadata: [String: JSONValue]?
    public let clientMessageID: String?

    public init(id: Int64, chatID: String, role: String, content: String, userID: Int64?, agentID: Int64?, threadID: String?, status: String, createdAt: String, components: [AptevaChatComponent]?, attachments: [AptevaConversationAttachment]?, metadata: [String: JSONValue]?, clientMessageID: String?) {
        self.id = id
        self.chatID = chatID
        self.role = role
        self.content = content
        self.userID = userID
        self.agentID = agentID
        self.threadID = threadID
        self.status = status
        self.createdAt = createdAt
        self.components = components
        self.attachments = attachments
        self.metadata = metadata
        self.clientMessageID = clientMessageID
    }

    public var createdDate: Date { parseAptevaDate(createdAt) ?? .distantPast }
    public var phase: String {
        metadata?["phase"]?.stringValue ?? "final"
    }

    public enum CodingKeys: String, CodingKey {
        case id, role, content, status, components, attachments, metadata
        case chatID = "chat_id"
        case userID = "user_id"
        case agentID = "agent_id"
        case threadID = "thread_id"
        case createdAt = "created_at"
        case clientMessageID = "client_message_id"
    }
}

public struct AptevaUnreadConversation: Decodable, Identifiable, Sendable {
    public let chatID: String
    public let instanceID: Int64
    public let instanceName: String
    public let title: String
    public let latestID: Int64
    public let latestRole: String
    public let latestPreview: String
    public let latestAt: String
    public let lastSeenID: Int64

    public var id: String { chatID }
    public var unreadCount: Int { latestID > lastSeenID ? 1 : 0 }

    public enum CodingKeys: String, CodingKey {
        case title
        case chatID = "chat_id"
        case instanceID = "instance_id"
        case instanceName = "instance_name"
        case latestID = "latest_id"
        case latestRole = "latest_role"
        case latestPreview = "latest_preview"
        case latestAt = "latest_at"
        case lastSeenID = "last_seen_id"
    }
}

public struct AptevaSSEEvent: Sendable {
    public let id: String?
    public let name: String?
    public let data: Data
}

public struct AptevaChatStreamFrame: Decodable, Sendable {
    public let chatID: String
    public let callID: String
    public let text: String
    public let phase: String?
    public let done: Bool

    public enum CodingKeys: String, CodingKey {
        case text, phase, done
        case chatID = "chat_id"
        case callID = "call_id"
    }
}
