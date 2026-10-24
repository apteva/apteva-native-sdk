import AVFoundation
import AVKit
import PDFKit
import QuickLook
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public indirect enum NativeJSONValue: Codable, Hashable, Sendable {
    case object([String: NativeJSONValue])
    case array([NativeJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: NativeJSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([NativeJSONValue].self) { self = .array(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var arrayValue: [NativeJSONValue]? {
        if case .array(let value) = self { value } else { nil }
    }

    public var objectValue: [String: NativeJSONValue]? {
        if case .object(let value) = self { value } else { nil }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { value } else { nil }
    }

    public var scalarString: String {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int64(value)) : String(value)
        case .bool(let value): value ? "true" : "false"
        case .array(let values): values.map(\.scalarString).joined(separator: ", ")
        case .object, .null: ""
        }
    }

    public func value(at selector: String) -> NativeJSONValue? {
        guard selector == "$" || selector.hasPrefix("$.") else { return nil }
        if selector == "$" { return self }
        return selector.dropFirst(2).split(separator: ".").reduce(Optional(self)) { current, component in
            guard case .object(let object)? = current else { return nil }
            return object[String(component)]
        }
    }
}

public enum NativeChatMessagePlacement: Sendable, Equatable {
    case append
    case prepend
}

public func nativeChatMessageID(_ message: NativeJSONValue, selector: String) -> String {
    message.value(at: selector)?.scalarString ?? ""
}

/// Combines a history snapshot with messages that may have arrived over SSE
/// while that snapshot was in flight. Live values win for duplicate IDs.
public func nativeChatMergingSnapshot(
    _ snapshot: [NativeJSONValue],
    preserving live: [NativeJSONValue],
    idSelector: String
) -> [NativeJSONValue] {
    var merged: [NativeJSONValue] = []
    var indexByID: [String: Int] = [:]

    for message in snapshot + live {
        let id = nativeChatMessageID(message, selector: idSelector)
        guard !id.isEmpty else { continue }
        if let index = indexByID[id] {
            merged[index] = message
        } else {
            indexByID[id] = merged.count
            merged.append(message)
        }
    }
    return merged
}

/// Applies a live event without ever creating two rows for one mapped ID.
/// Existing rows retain their position so an update cannot reorder history.
public func nativeChatInserting(
    _ message: NativeJSONValue,
    into messages: [NativeJSONValue],
    idSelector: String,
    explicitID: String? = nil,
    placement: NativeChatMessagePlacement = .append
) -> [NativeJSONValue] {
    let id = explicitID.flatMap { $0.isEmpty ? nil : $0 }
        ?? nativeChatMessageID(message, selector: idSelector)
    guard !id.isEmpty else { return messages }

    var result = messages
    if let index = result.firstIndex(where: {
        nativeChatMessageID($0, selector: idSelector) == id
    }) {
        result[index] = message
    } else if placement == .prepend {
        result.insert(message, at: 0)
    } else {
        result.append(message)
    }
    return result
}

public struct DeclaredNativeSurface: Decodable, Sendable {
    public let schema: String
    public let id: String
    public let version: String
    public let title: String
    public let description: String?
    public let icon: String
    public let context: DeclaredSurfaceContext
    public let state: [String: DeclaredSurfaceState]
    public let dataSources: [String: DeclaredSurfaceDataSource]
    public let primaryActions: [String]
    public let sections: [DeclaredSurfaceSection]
    public let destinations: [String: DeclaredSurfaceDestination]
    public let actions: [String: DeclaredSurfaceAction]
    public let resources: [String: DeclaredSurfaceResource]
    public let presentation: String?
    public let blocks: [DeclaredSurfaceBlock]
    public let navigation: DeclaredSurfaceNavigation?

    enum CodingKeys: String, CodingKey {
        case schema, id, version, title, description, icon, context, state, sections, destinations, actions, resources, presentation, blocks, navigation
        case dataSources = "data_sources"
        case primaryActions = "primary_actions"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(String.self, forKey: .schema)
        id = try values.decode(String.self, forKey: .id)
        version = try values.decode(String.self, forKey: .version)
        title = try values.decode(String.self, forKey: .title)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        icon = try values.decode(String.self, forKey: .icon)
        context = try values.decode(DeclaredSurfaceContext.self, forKey: .context)
        state = try values.decodeIfPresent([String: DeclaredSurfaceState].self, forKey: .state) ?? [:]
        dataSources = try values.decodeIfPresent([String: DeclaredSurfaceDataSource].self, forKey: .dataSources) ?? [:]
        primaryActions = try values.decodeIfPresent([String].self, forKey: .primaryActions) ?? []
        sections = try values.decodeIfPresent([DeclaredSurfaceSection].self, forKey: .sections) ?? []
        destinations = try values.decodeIfPresent([String: DeclaredSurfaceDestination].self, forKey: .destinations) ?? [:]
        actions = try values.decodeIfPresent([String: DeclaredSurfaceAction].self, forKey: .actions) ?? [:]
        resources = try values.decodeIfPresent([String: DeclaredSurfaceResource].self, forKey: .resources) ?? [:]
        presentation = try values.decodeIfPresent(String.self, forKey: .presentation)
        blocks = try values.decodeIfPresent([DeclaredSurfaceBlock].self, forKey: .blocks) ?? []
        navigation = try values.decodeIfPresent(DeclaredSurfaceNavigation.self, forKey: .navigation)
    }
}

public struct DeclaredSurfaceNavigation: Decodable, Sendable { public let surface: String }

public struct DeclaredSurfaceBlock: Decodable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let title: String?
    public let label: String?
    public let source: String?
    public let value: String?
    public let text: String?
    public let format: String?
    public let icon: String?
    public let items: String?
    public let item: DeclaredSurfaceItemMapping?
    public let metrics: [DeclaredSurfaceMetric]
    public let limit: Int?
    public let action: String?
    public let empty: DeclaredSurfaceSemanticState?
    public let visibleIf: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, label, source, value, text, format, icon, items, item, metrics, limit, action, empty
        case visibleIf = "visible_if"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = try values.decode(String.self, forKey: .type)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        value = try values.decodeIfPresent(String.self, forKey: .value)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        format = try values.decodeIfPresent(String.self, forKey: .format)
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        items = try values.decodeIfPresent(String.self, forKey: .items)
        item = try values.decodeIfPresent(DeclaredSurfaceItemMapping.self, forKey: .item)
        metrics = try values.decodeIfPresent([DeclaredSurfaceMetric].self, forKey: .metrics) ?? []
        limit = try values.decodeIfPresent(Int.self, forKey: .limit)
        action = try values.decodeIfPresent(String.self, forKey: .action)
        empty = try values.decodeIfPresent(DeclaredSurfaceSemanticState.self, forKey: .empty)
        visibleIf = try values.decodeIfPresent(String.self, forKey: .visibleIf)
    }
}

public struct DeclaredSurfaceMetric: Decodable, Sendable {
    public let label: String
    public let value: String
    public let format: String?
    public let icon: String?
}

public struct DeclaredSurfaceContext: Decodable, Sendable { let scope: String }

public struct DeclaredSurfaceState: Decodable, Sendable {
    public let type: String
    public let defaultValue: NativeJSONValue?
    public let persistence: String?
    enum CodingKeys: String, CodingKey { case type, persistence; case defaultValue = "default" }
}

public struct DeclaredSurfaceDataSource: Decodable, Sendable {
    public let request: DeclaredSurfaceRequest
    public let response: DeclaredSurfaceResponse
    public let pagination: DeclaredSurfacePagination?
    public let refresh: DeclaredSurfaceRefresh?
}

public struct DeclaredSurfacePagination: Decodable, Sendable {
    public let type: String
    public let requestKey: String?
    public let responsePath: String?
    public let pageSize: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case requestKey = "request_key"
        case responsePath = "response_path"
        case pageSize = "page_size"
    }
}

public struct DeclaredSurfaceRefresh: Decodable, Sendable {
    public let onAppear: Bool?
    public let pullToRefresh: Bool?

    enum CodingKeys: String, CodingKey {
        case onAppear = "on_appear"
        case pullToRefresh = "pull_to_refresh"
    }
}

public struct DeclaredSurfaceRequest: Decodable, Sendable {
    public let method: String
    public let path: String
    public let encoding: String?
    public let query: [String: NativeJSONValue]
    public let body: [String: NativeJSONValue]

    enum CodingKeys: String, CodingKey { case method, path, encoding, query, body }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        method = try values.decode(String.self, forKey: .method)
        path = try values.decode(String.self, forKey: .path)
        encoding = try values.decodeIfPresent(String.self, forKey: .encoding)
        query = try values.decodeIfPresent([String: NativeJSONValue].self, forKey: .query) ?? [:]
        body = try values.decodeIfPresent([String: NativeJSONValue].self, forKey: .body) ?? [:]
    }
}

public struct DeclaredSurfaceResponse: Decodable, Sendable {
    public let items: String?
    public let item: String?
    public let id: String?
    public let result: String?
    public let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items, item, id, result
        case nextCursor = "next_cursor"
    }
}

public struct DeclaredSurfaceSection: Decodable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let title: String?
    public let description: String?
    public let source: String?
    public let presentation: String?
    public let search: DeclaredSurfaceSearch?
    public let filters: [DeclaredSurfaceFilter]
    public let item: DeclaredSurfaceItemMapping?
    public let fields: [DeclaredSurfaceField]
    public let preview: DeclaredSurfacePreview?
    public let actions: [String]
    public let empty: DeclaredSurfaceSemanticState?
    public let component: String?
    public let chat: DeclaredSurfaceChatComponent?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, description, source, presentation, search, filters, item, fields, preview, actions, empty, component, chat
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        kind = try values.decode(String.self, forKey: .kind)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        presentation = try values.decodeIfPresent(String.self, forKey: .presentation)
        search = try values.decodeIfPresent(DeclaredSurfaceSearch.self, forKey: .search)
        filters = try values.decodeIfPresent([DeclaredSurfaceFilter].self, forKey: .filters) ?? []
        item = try values.decodeIfPresent(DeclaredSurfaceItemMapping.self, forKey: .item)
        fields = try values.decodeIfPresent([DeclaredSurfaceField].self, forKey: .fields) ?? []
        preview = try values.decodeIfPresent(DeclaredSurfacePreview.self, forKey: .preview)
        actions = try values.decodeIfPresent([String].self, forKey: .actions) ?? []
        empty = try values.decodeIfPresent(DeclaredSurfaceSemanticState.self, forKey: .empty)
        component = try values.decodeIfPresent(String.self, forKey: .component)
        chat = try values.decodeIfPresent(DeclaredSurfaceChatComponent.self, forKey: .chat)
    }
}

public struct DeclaredSurfaceChatComponent: Decodable, Sendable {
    public let conversationsSource: String
    public let messagesSource: String
    public let selectionState: String
    public let sendAction: String
    public let createAction: String?
    public let markSeenAction: String?
    public let conversation: DeclaredSurfaceChatConversationMapping
    public let message: DeclaredSurfaceChatMessageMapping
    public let subscription: DeclaredSurfaceSubscription?
    public let live: DeclaredSurfaceChatLiveMapping?

    enum CodingKeys: String, CodingKey {
        case conversationsSource = "conversations_source"
        case messagesSource = "messages_source"
        case selectionState = "selection_state"
        case sendAction = "send_action"
        case createAction = "create_action"
        case markSeenAction = "mark_seen_action"
        case conversation, message, subscription, live
    }
}

public struct DeclaredSurfaceChatLiveMapping: Decodable, Sendable {
    public let id: String?
    public let agentID: String?
    public let threadID: String?
    public let runID: String?
    public let text: String?
    public let phase: String?
    public let done: String?
    public let progress: DeclaredSurfaceChatProgressMapping?
    public let activity: DeclaredSurfaceChatActivityMapping?

    enum CodingKeys: String, CodingKey {
        case id, text, phase, done, progress, activity
        case agentID = "agent_id"
        case threadID = "thread_id"
        case runID = "run_id"
    }
}

public struct DeclaredSurfaceChatProgressMapping: Decodable, Sendable {
    public let value: String?
    public let phase: String?
    public let revision: String?
    public let toolName: String?
    public let callID: String?
    public let afterMessageID: String?

    enum CodingKeys: String, CodingKey {
        case value, phase, revision
        case toolName = "tool_name"
        case callID = "call_id"
        case afterMessageID = "after_message_id"
    }
}

public struct DeclaredSurfaceChatActivityMapping: Decodable, Sendable {
    public let value: String?
    public let id: String?
    public let revision: String?
    public let name: String?
    public let reason: String?
    public let status: String?
    public let durationMS: String?

    enum CodingKeys: String, CodingKey {
        case value, id, revision, name, reason, status
        case durationMS = "duration_ms"
    }
}

public struct DeclaredSurfaceChatConversationMapping: Decodable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let preview: String?
    public let updatedAt: String?
    public let unread: String?

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, preview, unread
        case updatedAt = "updated_at"
    }
}

public struct DeclaredSurfaceChatMessageMapping: Decodable, Sendable {
    public let id: String
    public let conversationID: String
    public let body: String
    public let author: String?
    public let role: String?
    public let createdAt: String?
    public let status: String?

    enum CodingKeys: String, CodingKey {
        case id, body, author, role, status
        case conversationID = "conversation_id"
        case createdAt = "created_at"
    }
}

public struct DeclaredSurfaceSubscription: Decodable, Sendable {
    public let request: DeclaredSurfaceRequest
    public let cursorQuery: String?
    public let events: [String: DeclaredSurfaceEventMapping]

    enum CodingKeys: String, CodingKey {
        case request, events
        case cursorQuery = "cursor_query"
    }
}

public struct DeclaredSurfaceEventMapping: Decodable, Sendable {
    public let operation: String
    public let source: String
    public let value: String?
    public let id: String?
}

public struct DeclaredSurfaceSearch: Decodable, Sendable {
    public let state: String
    public let placeholder: String?
    public let queryKey: String?
    enum CodingKeys: String, CodingKey { case state, placeholder; case queryKey = "query_key" }
}

public struct DeclaredSurfaceFilter: Decodable, Identifiable, Sendable {
    public let id: String
    public let type: String
    public let state: String
    public let label: String
    public let options: [DeclaredSurfaceOption]
    public let source: String?
    public let mapping: DeclaredSurfaceOptionMapping?

    enum CodingKeys: String, CodingKey { case id, type, state, label, options, source, mapping }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        type = try values.decode(String.self, forKey: .type)
        state = try values.decode(String.self, forKey: .state)
        label = try values.decode(String.self, forKey: .label)
        options = try values.decodeIfPresent([DeclaredSurfaceOption].self, forKey: .options) ?? []
        source = try values.decodeIfPresent(String.self, forKey: .source)
        mapping = try values.decodeIfPresent(DeclaredSurfaceOptionMapping.self, forKey: .mapping)
    }
}

public struct DeclaredSurfaceOption: Decodable, Sendable {
    public let label: String
    public let value: NativeJSONValue
}

public struct DeclaredSurfaceOptionMapping: Decodable, Sendable {
    public let value: String
    public let label: String
}

public struct DeclaredSurfaceItemMapping: Decodable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: [DeclaredSurfaceValue]
    public let icon: DeclaredSurfaceValue?
    public let badge: DeclaredSurfaceValue?
    public let destination: String?
    public let actions: [String]

    enum CodingKeys: String, CodingKey { case id, title, subtitle, icon, badge, destination, actions }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        subtitle = try values.decodeIfPresent([DeclaredSurfaceValue].self, forKey: .subtitle) ?? []
        icon = try values.decodeIfPresent(DeclaredSurfaceValue.self, forKey: .icon)
        badge = try values.decodeIfPresent(DeclaredSurfaceValue.self, forKey: .badge)
        destination = try values.decodeIfPresent(String.self, forKey: .destination)
        actions = try values.decodeIfPresent([String].self, forKey: .actions) ?? []
    }
}

public struct DeclaredSurfaceValue: Decodable, Sendable {
    public let value: String
    public let label: String?
    public let format: String?
    public let fallback: String?
}

public struct DeclaredSurfaceField: Decodable, Identifiable, Sendable {
    public let id: String?
    public let label: String
    public let value: String
    public let format: String?
    public let hidden: Bool?
    public var stableID: String { id ?? label }
}

public struct DeclaredSurfacePreview: Decodable, Sendable {
    public let path: String
    public let name: String?
    public let contentType: String?
    public let shareAction: String?
    public let deleteAction: String?
    enum CodingKeys: String, CodingKey {
        case path, name
        case contentType = "content_type"
        case shareAction = "share_action"
        case deleteAction = "delete_action"
    }
}

public struct DeclaredSurfaceSemanticState: Decodable, Sendable {
    public let title: String?
    public let description: String?
    public let icon: String?
}

public struct DeclaredSurfaceDestination: Decodable, Sendable {
    public let type: String
    public let title: String
    public let source: String?
    public let sections: [DeclaredSurfaceSection]
    public let actions: [String]

    enum CodingKeys: String, CodingKey { case type, title, source, sections, actions }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        title = try values.decode(String.self, forKey: .title)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        sections = try values.decode([DeclaredSurfaceSection].self, forKey: .sections)
        actions = try values.decodeIfPresent([String].self, forKey: .actions) ?? []
    }
}

public struct DeclaredSurfaceAction: Decodable, Sendable {
    public let type: String
    public let label: String
    public let icon: String?
    public let placements: [String]
    public let destructive: Bool?
    public let request: DeclaredSurfaceRequest
    public let fields: [DeclaredSurfaceInput]
    public let result: String?
    public let confirmation: DeclaredSurfaceConfirmation?
    public let success: DeclaredSurfaceActionSuccess?

    enum CodingKeys: String, CodingKey {
        case type, label, icon, placements, destructive, request, fields, result, confirmation, success
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        type = try values.decode(String.self, forKey: .type)
        label = try values.decode(String.self, forKey: .label)
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        placements = try values.decodeIfPresent([String].self, forKey: .placements) ?? []
        destructive = try values.decodeIfPresent(Bool.self, forKey: .destructive)
        request = try values.decode(DeclaredSurfaceRequest.self, forKey: .request)
        fields = try values.decodeIfPresent([DeclaredSurfaceInput].self, forKey: .fields) ?? []
        result = try values.decodeIfPresent(String.self, forKey: .result)
        confirmation = try values.decodeIfPresent(DeclaredSurfaceConfirmation.self, forKey: .confirmation)
        success = try values.decodeIfPresent(DeclaredSurfaceActionSuccess.self, forKey: .success)
    }
}

public struct DeclaredSurfaceInput: Decodable, Identifiable, Sendable {
    public let name: String
    public let type: String
    public let label: String?
    public let placeholder: String?
    public let required: Bool
    public let defaultValue: NativeJSONValue?
    public let options: [DeclaredSurfaceOption]
    public let resource: String?

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, type, label, placeholder, required, options, resource
        case defaultValue = "default"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        type = try values.decode(String.self, forKey: .type)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        placeholder = try values.decodeIfPresent(String.self, forKey: .placeholder)
        required = try values.decodeIfPresent(Bool.self, forKey: .required) ?? false
        defaultValue = try values.decodeIfPresent(NativeJSONValue.self, forKey: .defaultValue)
        options = try values.decodeIfPresent([DeclaredSurfaceOption].self, forKey: .options) ?? []
        resource = try values.decodeIfPresent(String.self, forKey: .resource)
    }
}

public struct DeclaredSurfaceActionSuccess: Decodable, Sendable {
    public let refresh: [String]
    public let dismiss: Bool
    public let toast: String?

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        refresh = try values.decodeIfPresent([String].self, forKey: .refresh) ?? []
        dismiss = try values.decodeIfPresent(Bool.self, forKey: .dismiss) ?? false
        toast = try values.decodeIfPresent(String.self, forKey: .toast)
    }

    enum CodingKeys: String, CodingKey { case refresh, dismiss, toast }
}

public struct DeclaredSurfaceResource: Decodable, Sendable {
    public let type: String
    public let label: String
    public let source: String
    public let mapping: DeclaredSurfaceResourceMapping
}

public struct DeclaredSurfaceResourceMapping: Decodable, Sendable {
    public let id: String
    public let label: String
    public let parent: String?
}

public struct DeclaredSurfaceConfirmation: Decodable, Sendable {
    public let title: String
    public let message: String?
    public let confirmLabel: String?
    enum CodingKeys: String, CodingKey { case title, message; case confirmLabel = "confirm_label" }
}

#if canImport(UIKit)
public struct DeclaredNativeSurfaceView: View {
    let descriptor: AptevaNativeSurfaceDescriptor
    let appName: String
    let projectID: String
    let client: AptevaAPIClient
    let chatDeepLink: NativeChatDeepLink?
    let onNotificationOpened: @MainActor () async -> Void

    public init(descriptor: AptevaNativeSurfaceDescriptor, appName: String, projectID: String, client: AptevaAPIClient,
                chatDeepLink: NativeChatDeepLink? = nil,
                onNotificationOpened: @escaping @MainActor () async -> Void = {}) {
        self.descriptor = descriptor
        self.appName = appName
        self.projectID = projectID
        self.client = client
        self.chatDeepLink = chatDeepLink
        self.onNotificationOpened = onNotificationOpened
    }

    @State private var surface: DeclaredNativeSurface?
    @State private var errorMessage: String?

    public var body: some View {
        Group {
            if let surface {
                DeclaredSurfaceContentView(surface: surface, appName: appName, projectID: projectID, client: client,
                                           chatDeepLink: chatDeepLink, onNotificationOpened: onNotificationOpened)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Surface unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                AptevaLoadingView(
                    "Loading \(descriptor.label)",
                    detail: "Preparing the native app view"
                )
            }
        }
        .navigationTitle(descriptor.label)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: descriptor.id) { await load() }
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        do {
            surface = try await client.nativeSurface(appName: appName, descriptor: descriptor, projectID: projectID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DeclaredSurfaceContentView: View {
    let surface: DeclaredNativeSurface
    let appName: String
    let projectID: String
    let client: AptevaAPIClient
    let chatDeepLink: NativeChatDeepLink?
    let onNotificationOpened: @MainActor () async -> Void

    @Environment(\.openURL) private var openURL
    @State private var state: [String: NativeJSONValue]
    @State private var records: [String: [NativeJSONValue]] = [:]
    @State private var dynamicOptions: [String: [ResolvedSurfaceOption]] = [:]
    @State private var search = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedItem: SelectedSurfaceItem?
    @State private var formTarget: PendingSurfaceForm?
    @State private var pendingConfirmation: PendingSurfaceAction?
    @State private var notice: SurfaceNotice?
    @State private var sharePayload: SharePayload?

    init(surface: DeclaredNativeSurface, appName: String, projectID: String, client: AptevaAPIClient,
         chatDeepLink: NativeChatDeepLink? = nil,
         onNotificationOpened: @escaping @MainActor () async -> Void = {}) {
        self.surface = surface
        self.appName = appName
        self.projectID = projectID
        self.client = client
        self.chatDeepLink = chatDeepLink
        self.onNotificationOpened = onNotificationOpened
        _state = State(initialValue: surface.state.mapValues { $0.defaultValue ?? .null })
        let initialSearch = surface.sections.compactMap(\.search).first.flatMap { surface.state[$0.state]?.defaultValue?.scalarString } ?? ""
        _search = State(initialValue: initialSearch)
    }

    var body: some View {
        if let section = surface.sections.first(where: { $0.component == "chat/v1" }),
           let chat = section.chat {
            if let chatDeepLink {
                DeclaredChatThreadView(
                    surface: surface, configuration: chat,
                    selection: NativeChatSelection(id: chatDeepLink.conversationID, value: chatDeepLink.conversation),
                    appName: appName, projectID: projectID, client: client,
                    targetMessageID: chatDeepLink.messageID,
                    onNotificationOpened: onNotificationOpened,
                    onConversationChanged: {}
                )
            } else {
                DeclaredChatComponentView(surface: surface, configuration: chat, appName: appName,
                                          projectID: projectID, client: client)
            }
        } else {
            standardSurface
        }
    }

    private var standardSurface: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                surfaceHeader

                if let errorMessage {
                    SurfaceRuntimeErrorBanner(message: errorMessage) { Task { await load() } }
                }

                ForEach(surface.sections) { section in
                    if section.kind == "collection" {
                        collection(section)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
        .background(AptevaPalette.background)
        .refreshable { await load() }
        .searchable(text: $search, prompt: surface.sections.compactMap(\.search).first?.placeholder ?? "Search")
        .onSubmit(of: .search) {
            guard let searchSpec = surface.sections.compactMap(\.search).first else { return }
            state[searchSpec.state] = .string(search)
            Task { await load() }
        }
        .toolbar {
            if !surface.primaryActions.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(surface.primaryActions, id: \.self) { actionID in
                            if let action = surface.actions[actionID] {
                                Button { perform(actionID, item: nil) } label: {
                                    Label(action.label, systemImage: nativeSurfaceSymbol(action.icon ?? "add"))
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .overlay {
            if isLoading && records.isEmpty {
                AptevaLoadingView("Loading \(surface.title)", compact: true)
                    .background(AptevaPalette.background.opacity(0.94))
            }
        }
        .sheet(item: $selectedItem) { selected in
            if let destination = selected.destination.flatMap({ surface.destinations[$0] }) {
                DeclaredSurfaceDetailView(
                    destination: destination,
                    item: selected.value,
                    surface: surface,
                    appName: appName,
                    projectID: projectID,
                    client: client,
                    onAction: perform
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $formTarget) { target in
            NativeSurfaceActionForm(
                action: target.action,
                item: target.item,
                surface: surface,
                appName: appName,
                projectID: projectID,
                client: client,
                stateValues: state,
                initialValues: initialFormValues(for: target.action, item: target.item)
            ) { input in
                try await submit(target.action, item: target.item, input: input)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $sharePayload) { payload in
            NativeShareSheet(items: [payload.value])
        }
        .alert(item: $notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("Done")))
        }
        .confirmationDialog(
            pendingConfirmation?.action.confirmation?.title ?? "Continue?",
            isPresented: Binding(get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } }),
            titleVisibility: .visible
        ) {
            if let pendingConfirmation {
                Button(pendingConfirmation.action.confirmation?.confirmLabel ?? pendingConfirmation.action.label, role: .destructive) {
                    Task { await execute(pendingConfirmation.action, item: pendingConfirmation.item, input: [:]) }
                    self.pendingConfirmation = nil
                }
                Button("Cancel", role: .cancel) { self.pendingConfirmation = nil }
            }
        } message: {
            if let message = pendingConfirmation?.action.confirmation?.message { Text(message) }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var surfaceHeader: some View {
        if let description = surface.description, !description.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: nativeSurfaceSymbol(surface.icon))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AptevaPalette.accent)
                    .frame(width: 44, height: 44)
                    .background(AptevaPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(AptevaPalette.muted)
            }
        }
    }

    @ViewBuilder
    private func collection(_ section: DeclaredSurfaceSection) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            if !section.filters.isEmpty { filterBar(section.filters) }
            HStack {
                SectionLabel(section.title ?? surface.title)
                Spacer()
                Text("\(records[section.id, default: []].count)")
                    .font(.apteva(.caption2, weight: .bold))
                    .foregroundStyle(AptevaPalette.dim)
            }

            let items = records[section.id, default: []]
            if items.isEmpty && !isLoading {
                GlassCard {
                    VStack(spacing: 9) {
                        Image(systemName: nativeSurfaceSymbol(section.empty?.icon ?? "empty"))
                            .font(.title2)
                            .foregroundStyle(AptevaPalette.dim)
                        Text(section.empty?.title ?? "Nothing here")
                            .font(.apteva(.headline, weight: .bold))
                        if let description = section.empty?.description {
                            Text(description).font(.apteva(.caption)).foregroundStyle(AptevaPalette.muted)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else if let mapping = section.item {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            Button {
                                selectedItem = SelectedSurfaceItem(value: item, destination: mapping.destination)
                            } label: {
                                HStack(spacing: 12) {
                                    let mime = resolve(mapping.icon?.value ?? "", item: item).scalarString
                                    Image(systemName: iconForValue(mime, format: mapping.icon?.format, fallback: mapping.icon?.fallback))
                                        .foregroundStyle(AptevaPalette.accent)
                                        .frame(width: 36, height: 36)
                                        .background(AptevaPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(resolve(mapping.title, item: item).scalarString)
                                            .font(.apteva(.subheadline, weight: .semibold))
                                            .foregroundStyle(AptevaPalette.text)
                                            .lineLimit(1)
                                        Text(mapping.subtitle.map { formatted($0, item: item) }.filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.apteva(.caption2))
                                            .foregroundStyle(AptevaPalette.muted)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if let badge = mapping.badge {
                                        Text(formatted(badge, item: item).uppercased())
                                            .font(.apteva(.caption2, weight: .bold))
                                            .foregroundStyle(AptevaPalette.accent)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AptevaPalette.dim)
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            if index < items.count - 1 { Divider().overlay(AptevaPalette.border).padding(.leading, 48) }
                        }
                    }
                }
            }
        }
    }

    private func filterBar(_ filters: [DeclaredSurfaceFilter]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(filters) { filter in
                    if filter.type == "toggle" {
                        Button {
                            let enabled = state[filter.state]?.scalarString == "true"
                            state[filter.state] = .bool(!enabled)
                            Task { await load() }
                        } label: {
                            Label(filter.label, systemImage: state[filter.state]?.scalarString == "true" ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(AptevaPalette.accent)
                    } else {
                        Menu {
                            ForEach(options(for: filter)) { option in
                                Button(option.label) {
                                    state[filter.state] = option.value
                                    Task { await load() }
                                }
                            }
                        } label: {
                            Label(selectedLabel(for: filter), systemImage: filter.type == "resource_picker" ? "folder" : "line.3.horizontal.decrease")
                        }
                        .buttonStyle(.bordered)
                        .tint(AptevaPalette.accent)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func options(for filter: DeclaredSurfaceFilter) -> [ResolvedSurfaceOption] {
        filter.options.map { ResolvedSurfaceOption(label: $0.label, value: $0.value) } + dynamicOptions[filter.id, default: []]
    }

    private func selectedLabel(for filter: DeclaredSurfaceFilter) -> String {
        let selected = state[filter.state]?.scalarString ?? ""
        return options(for: filter).first(where: { $0.value.scalarString == selected })?.label ?? filter.label
    }

    @MainActor
    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            for section in surface.sections where section.kind == "collection" {
                guard let sourceID = section.source, let source = surface.dataSources[sourceID] else { continue }
                let response = try await request(source.request, item: nil)
                records[section.id] = source.response.items.flatMap { response.value(at: $0)?.arrayValue } ?? []

                for filter in section.filters {
                    guard let filterSourceID = filter.source,
                          let filterSource = surface.dataSources[filterSourceID],
                          let mapping = filter.mapping else { continue }
                    let optionResponse = try await request(filterSource.request, item: nil)
                    let rows = filterSource.response.items.flatMap { optionResponse.value(at: $0)?.arrayValue } ?? []
                    dynamicOptions[filter.id] = rows.map {
                        ResolvedSurfaceOption(label: $0.value(at: mapping.label)?.scalarString ?? "", value: $0.value(at: mapping.value) ?? .null)
                    }.filter { !$0.label.isEmpty }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func perform(_ actionID: String, item: NativeJSONValue?) {
        guard let action = surface.actions[actionID] else { return }
        if action.destructive == true || action.type == "confirm" {
            pendingConfirmation = PendingSurfaceAction(action: action, item: item)
            return
        }
        if action.type == "form" {
            let target = PendingSurfaceForm(action: action, item: item)
            if selectedItem != nil {
                selectedItem = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    formTarget = target
                }
            } else {
                formTarget = target
            }
            return
        }
        if action.type == "file_upload" {
            notice = SurfaceNotice(title: action.label, message: "File upload forms are not available in this build yet.")
            return
        }
        if action.type == "open_url" {
            let path = resolveTemplate(action.request.path, item: item)
            if let url = client.nativeAppURL(appName: appName, projectID: projectID, path: path) { openURL(url) }
            return
        }
        Task { await execute(action, item: item, input: [:]) }
    }

    @MainActor
    private func execute(
        _ action: DeclaredSurfaceAction,
        item: NativeJSONValue?,
        input: [String: NativeJSONValue]
    ) async {
        do {
            let response = try await request(action.request, item: item, input: input)
            let result = action.result.flatMap { response.value(at: $0)?.scalarString }
            if action.type == "copy_result", let result {
                UIPasteboard.general.string = result
                notice = SurfaceNotice(title: "Copied", message: "The link is on your clipboard.")
            } else if action.type == "share_result", let result {
                sharePayload = SharePayload(value: result)
            }
            await load()
        } catch {
            notice = SurfaceNotice(title: "Action failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func submit(
        _ action: DeclaredSurfaceAction,
        item: NativeJSONValue?,
        input: [String: NativeJSONValue]
    ) async throws {
        do {
            _ = try await request(action.request, item: item, input: input)
            await load()
            if action.success?.dismiss == true { selectedItem = nil }
            if let toast = action.success?.toast, !toast.isEmpty {
                notice = SurfaceNotice(title: "Done", message: toast)
            }
        } catch {
            throw error
        }
    }

    private func request(
        _ request: DeclaredSurfaceRequest,
        item: NativeJSONValue?,
        input: [String: NativeJSONValue] = [:]
    ) async throws -> NativeJSONValue {
        let path = resolveTemplate(request.path, item: item, input: input)
        let query = request.query.mapValues { resolveJSON($0, item: item, input: input).scalarString }
        let body = request.body.mapValues { resolveJSON($0, item: item, input: input) }
        return try await client.nativeAppJSON(
            appName: appName,
            projectID: projectID,
            path: path,
            method: request.method,
            query: query,
            body: body.isEmpty ? nil : body
        )
    }

    private func resolve(
        _ expression: String,
        item: NativeJSONValue?,
        input: [String: NativeJSONValue] = [:]
    ) -> NativeJSONValue {
        if expression.hasPrefix("$item") {
            let selector = expression.replacingOccurrences(of: "$item", with: "$", options: .anchored)
            return item?.value(at: selector) ?? .null
        }
        if expression.hasPrefix("$state.") {
            return state[String(expression.dropFirst("$state.".count))] ?? .null
        }
        if expression.hasPrefix("$input.") {
            return input[String(expression.dropFirst("$input.".count))] ?? .null
        }
        return .string(resolveTemplate(expression, item: item, input: input))
    }

    private func resolveJSON(
        _ value: NativeJSONValue,
        item: NativeJSONValue?,
        input: [String: NativeJSONValue] = [:]
    ) -> NativeJSONValue {
        switch value {
        case .string(let expression): resolve(expression, item: item, input: input)
        case .object(let values): .object(values.mapValues { resolveJSON($0, item: item, input: input) })
        case .array(let values): .array(values.map { resolveJSON($0, item: item, input: input) })
        default: value
        }
    }

    private func resolveTemplate(
        _ template: String,
        item: NativeJSONValue?,
        input: [String: NativeJSONValue] = [:]
    ) -> String {
        var result = template
        if case .object(let object)? = item {
            for (key, value) in object { result = result.replacingOccurrences(of: "{item.\(key)}", with: value.scalarString) }
        }
        for (key, value) in state { result = result.replacingOccurrences(of: "{state.\(key)}", with: value.scalarString) }
        for (key, value) in input { result = result.replacingOccurrences(of: "{input.\(key)}", with: value.scalarString) }
        return result
    }

    private func initialFormValues(
        for action: DeclaredSurfaceAction,
        item: NativeJSONValue?
    ) -> [String: NativeJSONValue] {
        Dictionary(uniqueKeysWithValues: action.fields.map { field in
            let value = field.defaultValue.map { resolveJSON($0, item: item) } ?? defaultFormValue(for: field.type)
            return (field.name, value)
        })
    }

    private func defaultFormValue(for type: String) -> NativeJSONValue {
        switch type {
        case "boolean": .bool(false)
        case "integer", "number": .number(0)
        case "string_list": .array([])
        default: .string("")
        }
    }

    private func formatted(_ value: DeclaredSurfaceValue, item: NativeJSONValue?) -> String {
        let resolved = resolve(value.value, item: item)
        switch value.format {
        case "file_size": return ByteCountFormatter.string(fromByteCount: Int64(resolved.scalarString) ?? 0, countStyle: .file)
        case "tags": return resolved.scalarString
        default:
            guard resolved.scalarString.isEmpty, let fallback = value.fallback else {
                return resolved.scalarString
            }
            return resolve(fallback, item: item).scalarString
        }
    }

    private func iconForValue(_ value: String, format: String?, fallback: String?) -> String {
        guard format == "file_icon" else { return nativeSurfaceSymbol(value.isEmpty ? fallback ?? "file" : value) }
        if value.hasPrefix("image/") { return "photo" }
        if value.hasPrefix("video/") { return "play.rectangle" }
        if value.hasPrefix("audio/") { return "waveform" }
        if value == "application/pdf" { return "doc.richtext" }
        return "doc"
    }
}

private struct DeclaredChatComponentView: View {
    let surface: DeclaredNativeSurface
    let configuration: DeclaredSurfaceChatComponent
    let appName: String
    let projectID: String
    let client: AptevaAPIClient

    @State private var conversations: [NativeJSONValue] = []
    @State private var search = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var createTarget: PendingChatAction?

    private var mapping: DeclaredSurfaceChatConversationMapping { configuration.conversation }
    private var visibleConversations: [NativeJSONValue] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { item in
            let haystack = [
                chatValue(mapping.title, in: item),
                mapping.subtitle.map { chatValue($0, in: item) } ?? "",
                mapping.preview.map { chatValue($0, in: item) } ?? ""
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if isLoading && conversations.isEmpty {
                AptevaLoadingView("Loading conversations")
            } else if let errorMessage, conversations.isEmpty {
                ContentUnavailableView {
                    Label("Could not load conversations", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if visibleConversations.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No conversations" : "No matches",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(search.isEmpty ? "This app has no conversations yet." : "Try another search.")
                )
            } else {
                List(visibleConversations, id: \.self) { conversation in
                    let id = chatValue(mapping.id, in: conversation)
                    Group {
                        if id.isEmpty {
                            NativeChatConversationRow(item: conversation, mapping: mapping)
                        } else {
                            NavigationLink {
                                DeclaredChatThreadView(
                                    surface: surface,
                                    configuration: configuration,
                                    selection: NativeChatSelection(id: id, value: conversation),
                                    appName: appName,
                                    projectID: projectID,
                                    client: client,
                                    onConversationChanged: { await load(quietly: true) }
                                )
                            } label: {
                                NativeChatConversationRow(item: conversation, mapping: mapping)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("chat-conversation-\(id)")
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
            }
        }
        .background(AptevaPalette.background)
        .searchable(text: $search, prompt: "Search conversations")
        .toolbar {
            if let actionID = configuration.createAction,
               let action = surface.actions[actionID] {
                Button {
                    createTarget = PendingChatAction(action: action)
                } label: {
                    Image(systemName: nativeSurfaceSymbol(action.icon ?? "add"))
                }
                .accessibilityLabel(action.label)
            }
        }
        .sheet(item: $createTarget) { target in
            NativeSurfaceActionForm(
                action: target.action,
                item: nil,
                surface: surface,
                appName: appName,
                projectID: projectID,
                client: client,
                stateValues: surface.state.mapValues { $0.defaultValue ?? .null },
                initialValues: chatInitialValues(target.action.fields)
            ) { input in
                _ = try await chatRequest(
                    target.action.request,
                    state: surface.state.mapValues { $0.defaultValue ?? .null },
                    input: input,
                    appName: appName,
                    projectID: projectID,
                    client: client
                )
                await load(quietly: true)
            }
        }
        .task(id: "\(appName)|\(projectID)|\(surface.id)") { await load() }
    }

    @MainActor
    private func load(quietly: Bool = false) async {
        guard let source = surface.dataSources[configuration.conversationsSource] else { return }
        if !quietly { isLoading = true }
        defer { isLoading = false }
        do {
            let response = try await chatRequest(
                source.request,
                state: surface.state.mapValues { $0.defaultValue ?? .null },
                appName: appName,
                projectID: projectID,
                client: client
            )
            conversations = source.response.items.flatMap { response.value(at: $0)?.arrayValue } ?? []
            errorMessage = nil
        } catch {
            if !quietly { errorMessage = error.localizedDescription }
        }
    }
}

private struct DeclaredChatThreadView: View {
    let surface: DeclaredNativeSurface
    let configuration: DeclaredSurfaceChatComponent
    let selection: NativeChatSelection
    let appName: String
    let projectID: String
    let client: AptevaAPIClient
    let onConversationChanged: () async -> Void
    let targetMessageID: String?
    let onNotificationOpened: @MainActor () async -> Void

    @State private var state: [String: NativeJSONValue]
    @State private var messages: [NativeJSONValue] = []
    @State private var draft = ""
    @State private var nextCursor: String?
    @State private var streamCursor: String?
    @State private var activityText: String?
    @State private var liveResponses: [String: NativeChatLiveResponse] = [:]
    @State private var responseProgress: [String: NativeChatResponseProgress] = [:]
    @State private var toolActivities: [String: NativeChatToolActivity] = [:]
    @State private var isAwaitingResponse = false
    @State private var hasLiveTextInCurrentResponse = false
    @State private var isLoading = false
    @State private var isLoadingOlder = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var focusedMessageID: String?
    @State private var didOpenNotification = false

    init(
        surface: DeclaredNativeSurface,
        configuration: DeclaredSurfaceChatComponent,
        selection: NativeChatSelection,
        appName: String,
        projectID: String,
        client: AptevaAPIClient,
        targetMessageID: String? = nil,
        onNotificationOpened: @escaping @MainActor () async -> Void = {},
        onConversationChanged: @escaping () async -> Void
    ) {
        self.surface = surface
        self.configuration = configuration
        self.selection = selection
        self.appName = appName
        self.projectID = projectID
        self.client = client
        self.onConversationChanged = onConversationChanged
        self.targetMessageID = targetMessageID
        self.onNotificationOpened = onNotificationOpened
        var initialState = surface.state.mapValues { $0.defaultValue ?? .null }
        initialState[configuration.selectionState] = .string(selection.id)
        _state = State(initialValue: initialState)
    }

    private var title: String {
        chatValue(configuration.conversation.title, in: selection.value)
    }

    private var renderedMessages: [NativeChatRenderMessage] {
        messages.map { NativeChatRenderMessage(id: messageID($0), value: $0) }
    }

    private var liveScrollKey: String {
        let responses = liveResponses.values.sorted { $0.id < $1.id }.map { $0.id + $0.text }.joined()
        let progress = responseProgress.values.sorted { $0.id < $1.id }.map { $0.id + $0.phase + $0.toolName }.joined()
        let activities = toolActivities.values.sorted { $0.id < $1.id }.map { $0.id + $0.status + $0.reason }.joined()
        return responses + progress + activities + (isAwaitingResponse ? "waiting" : "")
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                SurfaceRuntimeErrorBanner(message: errorMessage) { Task { await openInitialHistory() } }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    // Keep each turn visually distinct without making the
                    // transcript feel disconnected.
                    LazyVStack(spacing: 14) {
                        if nextCursor != nil {
                            Button {
                                Task { await loadOlder() }
                            } label: {
                                if isLoadingOlder { ProgressView() } else { Text("Load older messages") }
                            }
                            .buttonStyle(.bordered)
                            .disabled(isLoadingOlder)
                        }

                        if isLoading && messages.isEmpty {
                            AptevaLoadingView(
                                "Loading messages",
                                minimumHeight: 180,
                                compact: true
                            )
                        } else if messages.isEmpty {
                            ContentUnavailableView(
                                "No messages",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("Send a message to start this conversation.")
                            )
                            .padding(.top, 40)
                        }

                        ForEach(renderedMessages) { message in
                            NativeChatMessageRow(item: message.value, mapping: configuration.message)
                                .background(message.id == focusedMessageID ? AptevaPalette.accent.opacity(0.12) : .clear,
                                            in: RoundedRectangle(cornerRadius: 16))
                                .id(message.id)
                                .accessibilityIdentifier("chat-message-\(message.id)")
                        }

                        NativeChatLiveArea(
                            responses: liveResponses.values.sorted { $0.createdAt < $1.createdAt },
                            progress: responseProgress.values.sorted { $0.revision < $1.revision },
                            activities: toolActivities.values.sorted { $0.sortOrder < $1.sortOrder },
                            fallbackActivity: activityText,
                            isAwaitingResponse: isAwaitingResponse,
                            hasLiveText: hasLiveTextInCurrentResponse
                        )

                        Color.clear.frame(height: 1).id("chat-bottom")
                    }
                    .padding(14)
                }
                .onChange(of: messages.count) { _, _ in
                    if focusedMessageID == nil && (didOpenNotification || targetMessageID == nil) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: liveScrollKey) { _, _ in
                    if focusedMessageID == nil && (didOpenNotification || targetMessageID == nil) {
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                }
                .task(id: focusedMessageID) {
                    guard let focusedMessageID else { return }
                    await Task.yield()
                    proxy.scrollTo(focusedMessageID, anchor: .center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

            NativeChatComposer(text: $draft, isSending: isSending) { await send() }
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AptevaPalette.background)
        .accessibilityIdentifier("chat-thread-\(selection.id)")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // Keep history and realtime as separate structured view tasks. SwiftUI
        // starts them together and cancels both when this thread disappears.
        // The stream-open reconciliation and ID merge below close both sides
        // of the race: events received during a snapshot are preserved, and a
        // stream that connects later reloads anything created in the gap.
        .task(id: "history|\(selection.id)") {
            await openInitialHistory()
        }
        .task(id: "subscription|\(selection.id)") {
            await runSubscription()
        }
    }

    @MainActor
    private func openInitialHistory() async {
        guard await loadMessages() else { return }
        do {
            _ = try await nativeChatNotificationHistory(
                initial: NativeChatHistoryPage(messages: messages, nextCursor: nextCursor),
                targetMessageID: targetMessageID, idSelector: configuration.message.id
            ) { cursor in
                guard await loadMessages(cursor: cursor, prepending: true) else {
                    throw AptevaAPIError.connection(errorMessage ?? "Could not load message history.")
                }
                return NativeChatHistoryPage(messages: messages, nextCursor: nextCursor)
            }
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription }
            return
        }
        guard !Task.isCancelled else { return }
        focusedMessageID = targetMessageID
        await markSeen()
        if !didOpenNotification {
            didOpenNotification = true
            await onNotificationOpened()
        }
    }

    @MainActor
    @discardableResult
    private func loadMessages(
        cursor: String? = nil,
        prepending: Bool = false,
        quietly: Bool = false
    ) async -> Bool {
        guard let source = surface.dataSources[configuration.messagesSource] else { return false }
        if prepending {
            isLoadingOlder = true
        } else if !quietly {
            isLoading = true
        }
        defer {
            if prepending {
                isLoadingOlder = false
            } else if !quietly {
                isLoading = false
            }
        }
        do {
            var extraQuery: [String: String] = [:]
            if let cursor, let key = source.pagination?.requestKey { extraQuery[key] = cursor }
            let response = try await chatRequest(
                source.request,
                state: state,
                extraQuery: extraQuery,
                appName: appName,
                projectID: projectID,
                client: client
            )
            let rows = source.response.items.flatMap { response.value(at: $0)?.arrayValue } ?? []
            if prepending {
                for row in rows.reversed() {
                    messages = nativeChatInserting(
                        row,
                        into: messages,
                        idSelector: configuration.message.id,
                        placement: .prepend
                    )
                }
            } else {
                messages = nativeChatMergingSnapshot(
                    rows,
                    preserving: messages,
                    idSelector: configuration.message.id
                )
            }
            let cursorSelector = source.response.nextCursor ?? source.pagination?.responsePath
            nextCursor = cursorSelector.flatMap { response.value(at: $0)?.scalarString }.flatMap { $0.isEmpty ? nil : $0 }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadOlder() async {
        guard let nextCursor else { return }
        await loadMessages(cursor: nextCursor, prepending: true)
    }

    @MainActor
    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !isSending,
              let action = surface.actions[configuration.sendAction] else { return }
        isSending = true
        focusedMessageID = nil
        // The composer already communicates the in-flight POST. Do not show
        // Thinking until the server acknowledges that an agent turn started.
        isAwaitingResponse = false
        hasLiveTextInCurrentResponse = false
        liveResponses.removeAll()
        responseProgress.removeAll()
        toolActivities.removeAll()
        activityText = nil
        defer { isSending = false }
        do {
            let response = try await chatRequest(
                action.request,
                state: state,
                input: ["text": .string(text)],
                appName: appName,
                projectID: projectID,
                client: client
            )
            draft = ""
            if let selector = action.result,
               let message = response.value(at: selector),
               message.objectValue != nil {
                upsert(message)
            } else {
                await loadMessages()
            }
            await onConversationChanged()
        } catch {
            isAwaitingResponse = false
            errorMessage = error.localizedDescription
        }
    }

    private func markSeen() async {
        guard let actionID = configuration.markSeenAction,
              let action = surface.actions[actionID] else { return }
        _ = try? await chatRequest(
            action.request,
            state: state,
            appName: appName,
            projectID: projectID,
            client: client
        )
    }

    private func runSubscription() async {
        guard let subscription = configuration.subscription else { return }
        var retrySeconds = 0.5
        while !Task.isCancelled {
            var query = subscription.request.query.mapValues {
                chatResolveJSON($0, state: state, input: [:]).scalarString
            }
            if let key = subscription.cursorQuery, let streamCursor { query[key] = streamCursor }
            let path = chatResolveTemplate(subscription.request.path, state: state, input: [:])
            do {
                for try await event in client.nativeAppEventStream(
                    appName: appName,
                    projectID: projectID,
                    path: path,
                    query: query
                ) {
                    guard !Task.isCancelled else { return }
                    if event.name == AptevaSSETransport.openEventName {
                        retrySeconds = 0.5
                        // Reconcile after every initial connect or reconnect.
                        // The transport continues buffering subsequent events
                        // while this request is in flight, and snapshot merge
                        // preserves any event already applied by the other task.
                        await loadMessages(quietly: true)
                        await markSeen()
                        continue
                    }
                    if let id = event.id, !id.isEmpty { streamCursor = id }
                    guard let name = event.name,
                          let mapping = subscription.events[name],
                          let payload = try? JSONDecoder().decode(NativeJSONValue.self, from: event.data) else { continue }
                    await apply(mapping, payload: payload)
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(retrySeconds))
            retrySeconds = min(retrySeconds * 2, 30)
        }
    }

    @MainActor
    private func apply(_ mapping: DeclaredSurfaceEventMapping, payload: NativeJSONValue) async {
        if mapping.operation == "invalidate" {
            if mapping.source == configuration.messagesSource { await loadMessages() }
            if mapping.source == configuration.conversationsSource { await onConversationChanged() }
            return
        }
        if mapping.operation == "set_activity", applyLiveFrame(payload) {
            return
        }
        guard let selector = mapping.value,
              let value = payload.value(at: selector) else { return }
        if mapping.operation == "set_activity" {
            activityText = value.scalarString.isEmpty ? nil : value.scalarString
            return
        }
        guard mapping.source == configuration.messagesSource else {
            await onConversationChanged()
            return
        }
        switch mapping.operation {
        case "append":
            messages = nativeChatInserting(
                value,
                into: messages,
                idSelector: configuration.message.id,
                explicitID: mapping.id.flatMap { payload.value(at: $0)?.scalarString }
            )
        case "prepend":
            messages = nativeChatInserting(
                value,
                into: messages,
                idSelector: configuration.message.id,
                explicitID: mapping.id.flatMap { payload.value(at: $0)?.scalarString },
                placement: .prepend
            )
        case "upsert": upsert(value, explicitID: mapping.id.flatMap { payload.value(at: $0)?.scalarString })
        case "remove":
            let id = mapping.id.flatMap { payload.value(at: $0)?.scalarString } ?? messageID(value)
            messages.removeAll { messageID($0) == id }
        default: break
        }
        await markSeen()
        await onConversationChanged()
    }

    private func upsert(_ message: NativeJSONValue, explicitID: String? = nil) {
        messages = nativeChatInserting(
            message,
            into: messages,
            idSelector: configuration.message.id,
            explicitID: explicitID
        )
        reconcileLiveState(with: message)
    }

    @MainActor
    private func applyLiveFrame(_ payload: NativeJSONValue) -> Bool {
        let live = configuration.live
        let progressSelector = live?.progress?.value ?? "$.response_progress"
        let activitySelector = live?.activity?.value ?? "$.tool_activity"
        let progressValue = payload.value(at: progressSelector)
        let activityValue = payload.value(at: activitySelector)
        let callID = chatMappedValue(live?.id, default: "$.call_id", in: payload)
        let agentID = chatMappedValue(live?.agentID, default: "$.agent_id", in: payload)
        let threadID = chatMappedValue(live?.threadID, default: "$.thread_id", in: payload)
        let runID = chatMappedValue(live?.runID, default: "$.run_id", in: payload)
        let text = chatMappedValue(live?.text, default: "$.text", in: payload)
        let phase = chatMappedValue(live?.phase, default: "$.phase", in: payload)
        let done = chatMappedValue(live?.done, default: "$.done", in: payload) == "true"
        var handled = false

        if let progressValue, progressValue.objectValue != nil {
            handled = true
            let mapping = live?.progress
            let progressPhase = chatMappedValue(mapping?.phase, default: "$.phase", in: progressValue)
            let revision = Int(chatMappedValue(mapping?.revision, default: "$.revision", in: progressValue)) ?? 0
            let toolName = chatMappedValue(mapping?.toolName, default: "$.tool_name", in: progressValue)
            let progressCallID = chatMappedValue(mapping?.callID, default: "$.call_id", in: progressValue)
            let afterMessageID = chatMappedValue(mapping?.afterMessageID, default: "$.after_message_id", in: progressValue)
            let key = [agentID, threadID].joined(separator: ":")
            if progressPhase == "idle" {
                responseProgress.removeValue(forKey: key)
                if !hasLiveTextInCurrentResponse {
                    isAwaitingResponse = false
                }
            } else if !progressPhase.isEmpty {
                responseProgress[key] = NativeChatResponseProgress(
                    id: key,
                    phase: progressPhase,
                    toolName: toolName,
                    callID: progressCallID,
                    afterMessageID: afterMessageID,
                    revision: revision
                )
                if !hasLiveTextInCurrentResponse {
                    isAwaitingResponse = true
                }
            }
        }

        if let activityValue, activityValue.objectValue != nil {
            handled = true
            let mapping = live?.activity
            let id = chatMappedValue(mapping?.id, default: "$.id", in: activityValue)
            if !id.isEmpty {
                let revision = Int(chatMappedValue(mapping?.revision, default: "$.revision", in: activityValue)) ?? 0
                let current = toolActivities[id]
                if current == nil || revision >= current!.revision {
                    toolActivities[id] = NativeChatToolActivity(
                        id: id,
                        name: chatMappedValue(mapping?.name, default: "$.name", in: activityValue),
                        reason: chatMappedValue(mapping?.reason, default: "$.reason", in: activityValue),
                        status: chatMappedValue(mapping?.status, default: "$.status", in: activityValue),
                        durationMS: Double(chatMappedValue(mapping?.durationMS, default: "$.duration_ms", in: activityValue)),
                        revision: revision,
                        sortOrder: Int(id) ?? revision
                    )
                }
                if !hasLiveTextInCurrentResponse {
                    isAwaitingResponse = true
                }
            }
        }

        if !callID.isEmpty {
            handled = true
            let key = [agentID, threadID, callID, runID].joined(separator: ":")
            liveResponses = nativeChatApplyingLiveResponseFrame(
                to: liveResponses,
                key: key,
                callID: callID,
                agentID: agentID,
                text: text,
                phase: phase,
                done: done
            )
            if !text.isEmpty {
                hasLiveTextInCurrentResponse = true
                isAwaitingResponse = false
            } else if phase == "acknowledgement", !hasLiveTextInCurrentResponse {
                isAwaitingResponse = true
            }
        }
        if handled { activityText = nil }
        return handled
    }

    private func reconcileLiveState(with message: NativeJSONValue) {
        let role = configuration.message.role.map { chatValue($0, in: message).lowercased() } ?? ""
        guard !["user", "human", "outgoing", "operator"].contains(role) else { return }
        let durableText = chatValue(configuration.message.body, in: message)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        liveResponses = liveResponses.filter { _, response in
            !response.isComplete &&
                response.text.trimmingCharacters(in: .whitespacesAndNewlines) != durableText
        }
        responseProgress.removeAll()
        toolActivities.removeAll()
        isAwaitingResponse = false
        hasLiveTextInCurrentResponse = false
    }

    private func messageID(_ message: NativeJSONValue) -> String {
        chatValue(configuration.message.id, in: message)
    }
}

private func chatMappedValue(_ selector: String?, default defaultSelector: String, in value: NativeJSONValue) -> String {
    value.value(at: selector ?? defaultSelector)?.scalarString ?? ""
}

private struct NativeChatRenderMessage: Identifiable {
    let id: String
    let value: NativeJSONValue
}

struct NativeChatLiveResponse: Identifiable, Equatable {
    let id: String
    let callID: String
    let agentID: String
    let text: String
    let phase: String
    let createdAt: Date
    let isComplete: Bool
}

/// Applies accumulated text frames without changing the row identity, and
/// retains the final streamed text after `done` until the durable message
/// arrives. Dropping it on `done` creates a visible empty gap and can expose a
/// stale progress label between the ephemeral and durable events.
func nativeChatApplyingLiveResponseFrame(
    to responses: [String: NativeChatLiveResponse],
    key: String,
    callID: String,
    agentID: String,
    text: String,
    phase: String,
    done: Bool,
    now: Date = Date()
) -> [String: NativeChatLiveResponse] {
    var result = responses
    if done {
        for (responseKey, response) in result
        where response.callID == callID && (agentID.isEmpty || response.agentID == agentID) {
            result[responseKey] = NativeChatLiveResponse(
                id: response.id,
                callID: response.callID,
                agentID: response.agentID,
                text: response.text,
                phase: response.phase,
                createdAt: response.createdAt,
                isComplete: true
            )
        }
        return result
    }

    guard !text.isEmpty || !phase.isEmpty else { return result }
    let existing = result[key]
    result[key] = NativeChatLiveResponse(
        id: key,
        callID: callID,
        agentID: agentID,
        text: text,
        phase: phase,
        createdAt: existing?.createdAt ?? now,
        isComplete: false
    )
    return result
}

private struct NativeChatResponseProgress: Identifiable {
    let id: String
    let phase: String
    let toolName: String
    let callID: String
    let afterMessageID: String
    let revision: Int
}

private struct NativeChatToolActivity: Identifiable {
    let id: String
    let name: String
    let reason: String
    let status: String
    let durationMS: Double?
    let revision: Int
    let sortOrder: Int
}

private struct NativeChatLiveArea: View {
    let responses: [NativeChatLiveResponse]
    let progress: [NativeChatResponseProgress]
    let activities: [NativeChatToolActivity]
    let fallbackActivity: String?
    let isAwaitingResponse: Bool
    let hasLiveText: Bool

    private var latestProgress: NativeChatResponseProgress? { progress.last }

    private var progressLabel: String? {
        guard !hasLiveText else { return nil }
        guard let latestProgress else {
            return isAwaitingResponse ? "Thinking…" : nil
        }
        switch latestProgress.phase {
        case "thinking": return "Thinking…"
        case "preparing": return "Preparing response…"
        case "preparing_tool":
            return latestProgress.toolName.isEmpty ? "Preparing a tool…" : "Preparing \(latestProgress.toolName)…"
        case "running": return "Working…"
        case "continuing": return "Continuing…"
        case "acknowledgement": return "Thinking…"
        default: return latestProgress.phase.replacingOccurrences(of: "_", with: " ").capitalized + "…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(activities) { activity in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: activity.status == "running" ? "hammer.fill" : activity.status == "failed" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(activity.status == "failed" ? Color.red : AptevaPalette.accent)
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(activity.name.isEmpty ? "Tool" : activity.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AptevaPalette.text)
                            if let durationMS = activity.durationMS, durationMS > 0, activity.status != "running" {
                                Text(nativeChatDuration(durationMS))
                                    .font(.caption2)
                                    .foregroundStyle(AptevaPalette.dim)
                            }
                        }
                        if !activity.reason.isEmpty {
                            Text(activity.reason)
                                .font(.caption)
                                .foregroundStyle(AptevaPalette.muted)
                                .lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                    if activity.status == "running" {
                        ProgressView().controlSize(.mini)
                    }
                }
                .padding(.vertical, 2)
            }

            ForEach(responses) { response in
                if !response.text.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(response.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.body)
                            .foregroundStyle(AptevaPalette.text)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !response.isComplete {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.mini)
                                Text("Responding…")
                                    .font(.caption2)
                                    .foregroundStyle(AptevaPalette.muted)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !hasLiveText,
               responses.allSatisfy({ $0.text.isEmpty }),
               let label = progressLabel ?? fallbackActivity,
               !label.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(AptevaPalette.muted)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

private func nativeChatDuration(_ milliseconds: Double) -> String {
    if milliseconds < 1000 { return "\(Int(milliseconds)) ms" }
    return String(format: "%.1f s", milliseconds / 1000)
}

private struct NativeChatConversationRow: View {
    let item: NativeJSONValue
    let mapping: DeclaredSurfaceChatConversationMapping

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(AptevaPalette.accent)
                .frame(width: 38, height: 38)
                .background(AptevaPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chatValue(mapping.title, in: item)).font(.headline).lineLimit(1)
                    Spacer()
                    if let updatedAt = mapping.updatedAt {
                        Text(chatValue(updatedAt, in: item)).font(.caption2).foregroundStyle(AptevaPalette.dim).lineLimit(1)
                    }
                }
                let detail = mapping.preview.map { chatValue($0, in: item) }
                    ?? mapping.subtitle.map { chatValue($0, in: item) }
                    ?? ""
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(AptevaPalette.muted).lineLimit(2)
                }
            }
            if let unread = mapping.unread,
               let count = Int(chatValue(unread, in: item)), count > 0 {
                Text("\(count)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AptevaPalette.accent, in: Capsule())
            }
        }
        .padding(.vertical, 6)
    }
}

private struct NativeChatMessageRow: View {
    let item: NativeJSONValue
    let mapping: DeclaredSurfaceChatMessageMapping

    private var role: String { mapping.role.map { chatValue($0, in: item).lowercased() } ?? "" }
    private var outgoing: Bool { ["user", "human", "outgoing", "operator"].contains(role) }
    private var system: Bool { role == "system" }
    // Web renderers naturally collapse whitespace around message content;
    // SwiftUI Text preserves leading newlines, which created apparently
    // random oversized gaps between otherwise adjacent turns.
    private var bodyText: String {
        chatValue(mapping.body, in: item)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    var body: some View {
        if system {
            Text(bodyText)
                .font(.caption2)
                .foregroundStyle(AptevaPalette.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        } else if outgoing {
            HStack(alignment: .bottom, spacing: 0) {
                Spacer(minLength: 32)
                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(AptevaPalette.text)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 17,
                            bottomLeadingRadius: 17,
                            bottomTrailingRadius: 5,
                            topTrailingRadius: 17
                        )
                        .fill(AptevaPalette.accent.opacity(0.15))
                    }
                    .overlay {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 17,
                            bottomLeadingRadius: 17,
                            bottomTrailingRadius: 5,
                            topTrailingRadius: 17
                        )
                        .stroke(AptevaPalette.accent.opacity(0.3), lineWidth: 1)
                    }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let author = mapping.author {
                    let value = chatValue(author, in: item)
                    if !value.isEmpty {
                        Text(value.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AptevaPalette.muted)
                    }
                }
                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(AptevaPalette.text)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NativeChatComposer: View {
    @Binding var text: String
    let isSending: Bool
    let onSend: () async -> Void

    private var canSend: Bool {
        !isSending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(.leading, 17)
                .padding(.trailing, 62)
                .padding(.vertical, 16)
                .frame(minHeight: 92, alignment: .topLeading)
                .accessibilityIdentifier("chat-message-input")

            Button {
                Task { await onSend() }
            } label: {
                if isSending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : AptevaPalette.dim)
                }
            }
            .frame(width: 44, height: 44)
            .background(canSend || isSending ? AptevaPalette.accent : Color.white.opacity(0.1), in: Circle())
            .padding(7)
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
            .accessibilityIdentifier("chat-send-button")
        }
        .background(AptevaPalette.raised, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(AptevaPalette.background)
    }
}

private struct NativeChatSelection: Identifiable, Hashable {
    let id: String
    let value: NativeJSONValue
}

private struct PendingChatAction: Identifiable {
    let id = UUID()
    let action: DeclaredSurfaceAction
}

private func chatValue(_ selector: String, in item: NativeJSONValue) -> String {
    item.value(at: selector)?.scalarString ?? ""
}

private func chatInitialValues(_ fields: [DeclaredSurfaceInput]) -> [String: NativeJSONValue] {
    Dictionary(uniqueKeysWithValues: fields.map { field in
        let value: NativeJSONValue
        if let defaultValue = field.defaultValue { value = defaultValue }
        else if field.type == "boolean" { value = .bool(false) }
        else if field.type == "integer" || field.type == "number" { value = .number(0) }
        else if field.type == "string_list" { value = .array([]) }
        else { value = .string("") }
        return (field.name, value)
    })
}

private func chatRequest(
    _ request: DeclaredSurfaceRequest,
    state: [String: NativeJSONValue],
    input: [String: NativeJSONValue] = [:],
    extraQuery: [String: String] = [:],
    appName: String,
    projectID: String,
    client: AptevaAPIClient
) async throws -> NativeJSONValue {
    let path = chatResolveTemplate(request.path, state: state, input: input)
    var query = request.query.mapValues { chatResolveJSON($0, state: state, input: input).scalarString }
    query.merge(extraQuery) { _, new in new }
    let body = request.body.mapValues { chatResolveJSON($0, state: state, input: input) }
    return try await client.nativeAppJSON(
        appName: appName,
        projectID: projectID,
        path: path,
        method: request.method,
        query: query,
        body: body.isEmpty ? nil : body
    )
}

private func chatResolveJSON(
    _ value: NativeJSONValue,
    state: [String: NativeJSONValue],
    input: [String: NativeJSONValue]
) -> NativeJSONValue {
    switch value {
    case .string(let expression):
        if expression.hasPrefix("$state.") { return state[String(expression.dropFirst("$state.".count))] ?? .null }
        if expression.hasPrefix("$input.") { return input[String(expression.dropFirst("$input.".count))] ?? .null }
        return .string(chatResolveTemplate(expression, state: state, input: input))
    case .object(let values): return .object(values.mapValues { chatResolveJSON($0, state: state, input: input) })
    case .array(let values): return .array(values.map { chatResolveJSON($0, state: state, input: input) })
    default: return value
    }
}

private func chatResolveTemplate(
    _ template: String,
    state: [String: NativeJSONValue],
    input: [String: NativeJSONValue]
) -> String {
    var result = template
    for (key, value) in state { result = result.replacingOccurrences(of: "{state.\(key)}", with: value.scalarString) }
    for (key, value) in input { result = result.replacingOccurrences(of: "{input.\(key)}", with: value.scalarString) }
    return result
}

private struct DeclaredSurfaceDetailView: View {
    let destination: DeclaredSurfaceDestination
    let item: NativeJSONValue
    let surface: DeclaredNativeSurface
    let appName: String
    let projectID: String
    let client: AptevaAPIClient
    let onAction: (String, NativeJSONValue?) -> Void

    @State private var expandedPreview: NativeFilePreviewTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(destination.sections) { section in
                        if section.kind == "file_preview", let preview = section.preview {
                            if let target = previewTarget(preview) {
                                NativeFilePreviewView(target: target, client: client, compact: true) {
                                    expandedPreview = target
                                }
                            } else {
                                ContentUnavailableView("Preview unavailable", systemImage: "doc.questionmark")
                            }
                        } else if section.kind == "properties" {
                            SectionLabel(section.title ?? "Details")
                            GlassCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(section.fields.filter { $0.hidden != true }.enumerated()), id: \.element.stableID) { index, field in
                                        HStack(alignment: .top) {
                                            Text(field.label).foregroundStyle(AptevaPalette.muted)
                                            Spacer()
                                            Text(format(field)).foregroundStyle(AptevaPalette.text).multilineTextAlignment(.trailing)
                                        }
                                        .font(.apteva(.caption))
                                        .padding(.vertical, 10)
                                        if index < section.fields.filter({ $0.hidden != true }).count - 1 { Divider().overlay(AptevaPalette.border) }
                                    }
                                }
                            }
                        }
                    }

                    if !destination.actions.isEmpty {
                        SectionLabel("Actions")
                        ForEach(destination.actions, id: \.self) { actionID in
                            if let action = surface.actions[actionID] {
                                Button {
                                    if action.type == "open_url", let target = destination.sections.compactMap(\.preview).compactMap(previewTarget).first {
                                        expandedPreview = target
                                    } else {
                                        onAction(actionID, item)
                                    }
                                } label: {
                                    Label(action.label, systemImage: nativeSurfaceSymbol(action.icon ?? "action"))
                                        .font(.apteva(.subheadline, weight: .semibold))
                                        .foregroundStyle(action.destructive == true ? AptevaPalette.error : AptevaPalette.text)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 13)
                                        .background(AptevaPalette.raised, in: RoundedRectangle(cornerRadius: 15))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(AptevaPalette.background)
            .navigationTitle(resolveTemplate(destination.title))
            .navigationBarTitleDisplayMode(.inline)
        }
        .fullScreenCover(item: $expandedPreview) { target in
            NativeFilePreviewScreen(target: target, client: client)
        }
    }

    private func previewTarget(_ preview: DeclaredSurfacePreview) -> NativeFilePreviewTarget? {
        let path = resolveTemplate(preview.path)
        guard let url = client.nativeAppURL(appName: appName, projectID: projectID, path: path) else { return nil }
        let name = preview.name.map(resolve)?.scalarString
        let contentType = preview.contentType.map(resolve)?.scalarString
        return NativeFilePreviewTarget(
            url: url,
            appName: appName,
            projectID: projectID,
            path: path,
            name: name?.isEmpty == false ? name! : url.lastPathComponent,
            contentType: contentType ?? "application/octet-stream"
        )
    }

    private func resolve(_ expression: String) -> NativeJSONValue {
        guard expression.hasPrefix("$item") else { return .string(resolveTemplate(expression)) }
        return item.value(at: expression.replacingOccurrences(of: "$item", with: "$", options: .anchored)) ?? .null
    }

    private func resolveTemplate(_ template: String) -> String {
        var result = template
        if case .object(let object) = item {
            for (key, value) in object { result = result.replacingOccurrences(of: "{item.\(key)}", with: value.scalarString) }
        }
        return result
    }

    private func format(_ field: DeclaredSurfaceField) -> String {
        let value = resolve(field.value)
        if field.format == "file_size" { return ByteCountFormatter.string(fromByteCount: Int64(value.scalarString) ?? 0, countStyle: .file) }
        return value.scalarString
    }
}

private struct NativeFilePreviewTarget: Identifiable {
    let url: URL
    let appName: String
    let projectID: String
    let path: String
    let name: String
    let contentType: String

    var id: String { url.absoluteString }
}

private struct NativeFilePreviewScreen: View {
    let target: NativeFilePreviewTarget
    let client: AptevaAPIClient

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                NativeFilePreviewView(target: target, client: client, compact: false)
                    .padding(16)
            }
            .background(AptevaPalette.background)
            .navigationTitle(target.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct NativeFilePreviewView: View {
    let target: NativeFilePreviewTarget
    let client: AptevaAPIClient
    let compact: Bool
    var onExpand: (() -> Void)?

    @State private var image: UIImage?
    @State private var pdfDocument: PDFDocument?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isLoading = true
    @State private var isPreparingQuickLook = false
    @State private var errorMessage: String?
    @State private var quickLookItem: NativeQuickLookItem?

    init(target: NativeFilePreviewTarget, client: AptevaAPIClient, compact: Bool, onExpand: (() -> Void)? = nil) {
        self.target = target
        self.client = client
        self.compact = compact
        self.onExpand = onExpand
    }

    private var kind: NativeFilePreviewKind {
        let type = target.contentType.lowercased()
        if type.hasPrefix("image/") { return .image }
        if type.hasPrefix("video/") { return .video }
        if type.hasPrefix("audio/") { return .audio }
        if type == "application/pdf" { return .pdf }
        return .other
    }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("Preview unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") { Task { await prepare() } }
                    }
                } else if isLoading {
                    AptevaLoadingView(
                        "Loading preview",
                        minimumHeight: compact ? 180 : 360,
                        compact: compact
                    )
                } else {
                    previewContent
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))

            if compact, kind != .video, let onExpand {
                Button(action: onExpand) {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.apteva(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AptevaPalette.raised, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: target.id) { await prepare() }
        .onDisappear { player?.pause() }
        .sheet(item: $quickLookItem) { item in
            NativeQuickLookController(url: item.url)
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch kind {
        case .image:
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: compact ? 280 : 720)
                    .background(Color.black.opacity(0.22))
            }
        case .video:
            if let player {
                NativeVideoPlayerView(player: player, compact: compact, onExpand: onExpand)
            }
        case .audio:
            if let player {
                VStack(spacing: 20) {
                    Image(systemName: "waveform")
                        .font(.system(size: compact ? 44 : 64, weight: .light))
                        .foregroundStyle(AptevaPalette.accent)
                    Text(target.name)
                        .font(.apteva(.subheadline, weight: .semibold))
                        .foregroundStyle(AptevaPalette.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Button {
                        if isPlaying { player.pause() } else { player.play() }
                        isPlaying.toggle()
                    } label: {
                        Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                            .font(.apteva(.headline, weight: .bold))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(AptevaPalette.accent, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, minHeight: compact ? 230 : 380)
                .padding(24)
                .background(AptevaPalette.raised)
            }
        case .pdf:
            if let pdfDocument {
                NativePDFDocumentView(document: pdfDocument)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 340 : 760)
                    .background(Color.white)
            }
        case .other:
            VStack(spacing: 18) {
                Image(systemName: "doc")
                    .font(.system(size: compact ? 46 : 64, weight: .light))
                    .foregroundStyle(AptevaPalette.accent)
                Text(target.name)
                    .font(.apteva(.subheadline, weight: .semibold))
                    .foregroundStyle(AptevaPalette.text)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await openQuickLook() }
                } label: {
                    if isPreparingQuickLook {
                        ProgressView()
                    } else {
                        Label("Open with Quick Look", systemImage: "eye")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AptevaPalette.accent)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 220 : 360)
            .padding(24)
            .background(AptevaPalette.raised)
        }
    }

    @MainActor
    private func prepare() async {
        player?.pause()
        player = nil
        image = nil
        pdfDocument = nil
        errorMessage = nil
        isLoading = true

        do {
            switch kind {
            case .image:
                let data = try await client.nativeAppData(appName: target.appName, projectID: target.projectID, path: target.path)
                guard let decoded = UIImage(data: data) else { throw AptevaAPIError.invalidResponse }
                image = decoded
            case .pdf:
                let data = try await client.nativeAppData(appName: target.appName, projectID: target.projectID, path: target.path)
                guard let document = PDFDocument(data: data) else { throw AptevaAPIError.invalidResponse }
                pdfDocument = document
            case .video, .audio:
                // AVFoundation cannot attach our bearer credential to an
                // arbitrary remote asset request. Download through the
                // authenticated API client, then retain native playback.
                let localURL = try await client.nativeAppDownload(
                    appName: target.appName,
                    projectID: target.projectID,
                    path: target.path,
                    suggestedName: target.name
                )
                let asset = AVURLAsset(url: localURL)
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            case .other:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func openQuickLook() async {
        isPreparingQuickLook = true
        defer { isPreparingQuickLook = false }
        do {
            let url = try await client.nativeAppDownload(
                appName: target.appName,
                projectID: target.projectID,
                path: target.path,
                suggestedName: target.name
            )
            quickLookItem = NativeQuickLookItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum NativeFilePreviewKind {
    case image, video, audio, pdf, other
}

private struct NativeVideoPlayerView: View {
    let player: AVPlayer
    let compact: Bool
    var onExpand: (() -> Void)?

    @State private var isPlaying = false
    @State private var controlsVisible = true
    @State private var currentTime = 0.0
    @State private var duration = 0.0
    @State private var isScrubbing = false

    var body: some View {
        ZStack {
            NativeAVPlayerLayerView(player: player)
                .background(Color.black)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) { controlsVisible.toggle() }
                }

            if controlsVisible {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Text(videoTime(currentTime))
                            .frame(width: 42, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { currentTime },
                                set: { currentTime = $0 }
                            ),
                            in: 0...max(duration, 0.1),
                            onEditingChanged: { editing in
                                isScrubbing = editing
                                if !editing {
                                    player.seek(to: CMTime(seconds: currentTime, preferredTimescale: 600))
                                }
                            }
                        )
                        .tint(AptevaPalette.accent)

                        Text("−\(videoTime(max(duration - currentTime, 0)))")
                            .frame(width: 48, alignment: .trailing)

                        if compact, let onExpand {
                            Button(action: onExpand) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .frame(width: 32, height: 32)
                                    .background(.white.opacity(0.12), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.64), in: Capsule())
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 230 : 520)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .task {
            while !Task.isCancelled {
                if !isScrubbing {
                    let seconds = player.currentTime().seconds
                    if seconds.isFinite { currentTime = max(seconds, 0) }
                }
                if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
                    duration = seconds
                }
                isPlaying = player.rate > 0
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onDisappear { player.pause() }
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                guard !Task.isCancelled, isPlaying else { return }
                withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
            }
        }
    }

    private func videoTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct NativeAVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> NativeAVPlayerView {
        let view = NativeAVPlayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: NativeAVPlayerView, context: Context) {
        view.playerLayer.player = player
    }
}

private final class NativeAVPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct NativePDFDocumentView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = document
    }
}

private struct NativeQuickLookItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct NativeQuickLookController: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}

struct ResolvedSurfaceOption: Identifiable, Equatable {
    let label: String
    let value: NativeJSONValue
    var id: String { label + "\u{0}" + value.scalarString }
}

func nativeSurfaceResourceOptions(
    response: NativeJSONValue,
    source: DeclaredSurfaceDataSource,
    mapping: DeclaredSurfaceResourceMapping
) -> [ResolvedSurfaceOption] {
    let rows = source.response.items
        .flatMap { response.value(at: $0)?.arrayValue }
        ?? []
    return rows.compactMap { row in
        let label = row.value(at: mapping.label)?.scalarString ?? ""
        let value = row.value(at: mapping.id) ?? .null
        guard !label.isEmpty, value != .null, !value.scalarString.isEmpty else { return nil }
        return ResolvedSurfaceOption(label: label, value: value)
    }
}

private enum NativeSurfaceResourceError: LocalizedError {
    case missingResource(String)
    case missingSource(resource: String, source: String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let resource):
            "The form references the undeclared resource ‘\(resource)’."
        case .missingSource(let resource, let source):
            "The resource ‘\(resource)’ references the undeclared data source ‘\(source)’."
        }
    }
}

private struct SelectedSurfaceItem: Identifiable {
    let id = UUID()
    let value: NativeJSONValue
    let destination: String?
}

private struct PendingSurfaceAction {
    let action: DeclaredSurfaceAction
    let item: NativeJSONValue?
}

private struct PendingSurfaceForm: Identifiable {
    let id = UUID()
    let action: DeclaredSurfaceAction
    let item: NativeJSONValue?
}

private struct NativeSurfaceActionForm: View {
    let action: DeclaredSurfaceAction
    let item: NativeJSONValue?
    let surface: DeclaredNativeSurface
    let appName: String
    let projectID: String
    let client: AptevaAPIClient
    let stateValues: [String: NativeJSONValue]
    let onSubmit: ([String: NativeJSONValue]) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: NativeJSONValue]
    @State private var resources: [String: [ResolvedSurfaceOption]] = [:]
    @State private var isLoadingResources = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        action: DeclaredSurfaceAction,
        item: NativeJSONValue?,
        surface: DeclaredNativeSurface,
        appName: String,
        projectID: String,
        client: AptevaAPIClient,
        stateValues: [String: NativeJSONValue],
        initialValues: [String: NativeJSONValue],
        onSubmit: @escaping ([String: NativeJSONValue]) async throws -> Void
    ) {
        self.action = action
        self.item = item
        self.surface = surface
        self.appName = appName
        self.projectID = projectID
        self.client = client
        self.stateValues = stateValues
        self.onSubmit = onSubmit
        _values = State(initialValue: initialValues)
    }

    var body: some View {
        NavigationStack {
            Form {
                ForEach(action.fields) { field in
                    fieldView(field)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.apteva(.caption))
                            .foregroundStyle(AptevaPalette.error)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AptevaPalette.background)
            .navigationTitle(action.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting { ProgressView().controlSize(.small) }
                        else { Text(submitLabel) }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(AptevaPalette.accent)
                    .disabled(isSubmitting || !isValid)
                }
            }
            .overlay {
                if isLoadingResources {
                    AptevaLoadingView(
                        "Loading options",
                        minimumHeight: 96,
                        compact: true
                    )
                    .frame(maxWidth: 220)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .task { await loadResources() }
        }
    }

    @ViewBuilder
    private func fieldView(_ field: DeclaredSurfaceInput) -> some View {
        let label = fieldLabel(field)
        switch field.type {
        case "multiline":
            Section(label) {
                TextEditor(text: stringBinding(field.name))
                    .frame(minHeight: 96)
            }
        case "password":
            SecureField(field.placeholder ?? label, text: stringBinding(field.name))
        case "boolean":
            Toggle(label, isOn: boolBinding(field.name))
                .tint(AptevaPalette.accent)
        case "choice":
            Picker(label, selection: optionBinding(field, options: field.options.map { ResolvedSurfaceOption(label: $0.label, value: $0.value) })) {
                if !field.required { Text("None").tag("") }
                ForEach(field.options, id: \.label) { option in
                    Text(option.label).tag(option.value.scalarString)
                }
            }
        case "resource":
            resourceField(field, label: label)
        case "integer":
            TextField(field.placeholder ?? label, text: numericBinding(field.name, integer: true))
                .keyboardType(.numberPad)
        case "number":
            TextField(field.placeholder ?? label, text: numericBinding(field.name, integer: false))
                .keyboardType(.decimalPad)
        case "string_list":
            TextField(field.placeholder ?? "Comma-separated values", text: listBinding(field.name))
        case "url":
            TextField(field.placeholder ?? label, text: stringBinding(field.name))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        default:
            TextField(field.placeholder ?? label, text: stringBinding(field.name))
        }
    }

    @ViewBuilder
    private func resourceField(_ field: DeclaredSurfaceInput, label: String) -> some View {
        let options = field.resource.flatMap { resources[$0] } ?? []
        let selection = values[field.name]?.scalarString ?? ""

        if options.isEmpty {
            HStack {
                Text(label)
                Spacer()
                if isLoadingResources {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("No options available")
                        .foregroundStyle(AptevaPalette.dim)
                }
            }
            .accessibilityIdentifier("resource-picker-\(field.name)")
        } else {
            Menu {
                if !field.required {
                    Button("None") { values[field.name] = .string("") }
                }
                ForEach(options) { option in
                    Button {
                        values[field.name] = option.value
                    } label: {
                        if option.value.scalarString == selection {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                    .accessibilityIdentifier("resource-option-\(field.name)-\(option.value.scalarString)")
                }
            } label: {
                HStack {
                    Text(label)
                        .foregroundStyle(AptevaPalette.text)
                    Spacer()
                    Text(options.first(where: { $0.value.scalarString == selection })?.label ?? "Select")
                        .foregroundStyle(selection.isEmpty ? AptevaPalette.dim : AptevaPalette.text)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(AptevaPalette.dim)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("resource-picker-\(field.name)")
        }
    }

    private var submitLabel: String {
        action.label
    }

    private var isValid: Bool {
        action.fields.allSatisfy { field in
            guard field.required else { return true }
            let value = values[field.name] ?? .null
            switch value {
            case .string(let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .array(let rows): return !rows.isEmpty
            case .null: return false
            default: return true
            }
        }
    }

    private func fieldLabel(_ field: DeclaredSurfaceInput) -> String {
        let base = field.label?.isEmpty == false
            ? field.label!
            : field.name.replacingOccurrences(of: "_", with: " ").capitalized
        return field.required ? "\(base) *" : base
    }

    private func stringBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { values[name]?.scalarString ?? "" },
            set: { values[name] = .string($0) }
        )
    }

    private func boolBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { values[name]?.boolValue ?? false },
            set: { values[name] = .bool($0) }
        )
    }

    private func numericBinding(_ name: String, integer: Bool) -> Binding<String> {
        Binding(
            get: { values[name]?.scalarString ?? "" },
            set: { text in
                guard !text.isEmpty else { values[name] = .null; return }
                if integer, let value = Int64(text) { values[name] = .number(Double(value)) }
                else if !integer, let value = Double(text) { values[name] = .number(value) }
            }
        )
    }

    private func listBinding(_ name: String) -> Binding<String> {
        Binding(
            get: { values[name]?.arrayValue?.map(\.scalarString).joined(separator: ", ") ?? "" },
            set: { text in
                values[name] = .array(
                    text.split(whereSeparator: { $0 == "," || $0 == "\n" })
                        .map { .string($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .filter { !$0.scalarString.isEmpty }
                )
            }
        )
    }

    private func optionBinding(
        _ field: DeclaredSurfaceInput,
        options: [ResolvedSurfaceOption]
    ) -> Binding<String> {
        Binding(
            get: { values[field.name]?.scalarString ?? "" },
            set: { selection in
                values[field.name] = options.first(where: { $0.value.scalarString == selection })?.value ?? .string(selection)
            }
        )
    }

    private func submit() {
        guard isValid else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await onSubmit(values)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    @MainActor
    private func loadResources() async {
        let referenced = Set(action.fields.compactMap(\.resource))
        guard !referenced.isEmpty else { return }
        isLoadingResources = true
        defer { isLoadingResources = false }
        do {
            for resourceID in referenced {
                guard let resource = surface.resources[resourceID] else {
                    throw NativeSurfaceResourceError.missingResource(resourceID)
                }
                guard let source = surface.dataSources[resource.source] else {
                    throw NativeSurfaceResourceError.missingSource(resource: resourceID, source: resource.source)
                }
                let query = source.request.query.mapValues { resolve($0).scalarString }
                let body = source.request.body.mapValues(resolve)
                let response = try await client.nativeAppJSON(
                    appName: appName,
                    projectID: projectID,
                    path: source.request.path,
                    method: source.request.method,
                    query: query,
                    body: body.isEmpty ? nil : body
                )
                resources[resourceID] = nativeSurfaceResourceOptions(
                    response: response,
                    source: source,
                    mapping: resource.mapping
                )
            }
        } catch {
            errorMessage = "Could not load form options: \(error.localizedDescription)"
        }
    }

    private func resolve(_ value: NativeJSONValue) -> NativeJSONValue {
        guard case .string(let expression) = value else { return value }
        if expression.hasPrefix("$state.") {
            return stateValues[String(expression.dropFirst("$state.".count))] ?? .null
        }
        if expression.hasPrefix("$item") {
            let selector = expression.replacingOccurrences(of: "$item", with: "$", options: .anchored)
            return item?.value(at: selector) ?? .null
        }
        return value
    }
}

private struct SurfaceNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let value: String
}

private struct NativeShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct SurfaceRuntimeErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AptevaPalette.error)
            Text(message)
                .font(.caption)
                .foregroundStyle(AptevaPalette.text)
            Spacer()
            Button("Retry", action: retry)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AptevaPalette.accent)
        }
        .padding(13)
        .background(AptevaPalette.error.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

public func nativeSurfaceSymbol(_ semantic: String) -> String {
    switch semantic.lowercased() {
    case "folder", "files": "folder.fill"
    case "list-checks", "checklist", "tasks": "checklist"
    case "calendar", "schedule": "calendar"
    case "history", "recent": "clock.arrow.circlepath"
    case "check-circle", "success": "checkmark.circle.fill"
    case "inbox": "tray.full"
    case "activity": "waveform.path.ecg"
    case "alert", "warning": "exclamationmark.triangle.fill"
    case "report": "doc.text.fill"
    case "approval": "checkmark.seal.fill"
    case "upload": "square.and.arrow.up"
    case "link": "link"
    case "open", "external-link": "arrow.up.right.square"
    case "share": "square.and.arrow.up"
    case "copy": "doc.on.doc"
    case "move": "folder.badge.gearshape"
    case "tag": "tag"
    case "visibility", "eye": "eye"
    case "delete", "trash": "trash"
    case "empty": "tray"
    case "file": "doc"
    case "add": "plus"
    default:
        semantic.contains(".") && !semantic.contains("/") && !semantic.contains("?")
            ? semantic
            : "square.grid.2x2"
    }
}
#endif
