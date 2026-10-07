import Foundation

public struct AptevaAgent: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let status: String
    public let mode: String
    public let directive: String?
    public let kind: String?
    public let createdAt: String?

    public enum CodingKeys: String, CodingKey {
        case id, name, status, mode, directive, kind
        case createdAt = "created_at"
    }
}

public struct AptevaAgentConfiguration: Decodable, Sendable {
    public let directive: String
    public let mode: String
    public let providers: [AptevaAgentProviderConfiguration]
    public let mcpServers: [AptevaMCPServerConfiguration]

    public enum CodingKeys: String, CodingKey {
        case directive, mode, providers
        case mcpServers = "mcp_servers"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        directive = try values.decodeIfPresent(String.self, forKey: .directive) ?? ""
        mode = try values.decode(String.self, forKey: .mode)
        providers = try values.decodeIfPresent([AptevaAgentProviderConfiguration].self, forKey: .providers) ?? []
        mcpServers = try values.decodeIfPresent([AptevaMCPServerConfiguration].self, forKey: .mcpServers) ?? []
    }
}

public struct AptevaAgentProviderConfiguration: Codable, Hashable, Sendable {
    public let name: String
    public let isDefault: Bool
    public let models: [String: String]?

    public enum CodingKeys: String, CodingKey {
        case name, models
        case isDefault = "default"
    }

    public init(name: String, isDefault: Bool, models: [String: String]? = nil) {
        self.name = name
        self.isDefault = isDefault
        self.models = models
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        isDefault = try values.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        models = try values.decodeIfPresent([String: String].self, forKey: .models)
    }
}

public struct AptevaMCPServerConfiguration: Decodable, Hashable, Sendable {
    public let name: String
    public let transport: String?
    public let url: String?
    public let command: String?
    public let arguments: [String]?
    public let connected: Bool?

    public enum CodingKeys: String, CodingKey {
        case name, transport, url, command, connected
        case arguments = "args"
    }
}

public struct AptevaRuntimeConnection: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let appSlug: String
    public let appName: String
    public let providerKey: String
    public let role: String
    public let projectID: String?
    public let scope: String
    public let isPrimary: Bool

    public enum CodingKeys: String, CodingKey {
        case id, name, role, scope
        case appSlug = "app_slug"
        case appName = "app_name"
        case providerKey = "provider_key"
        case projectID = "project_id"
        case isPrimary = "is_primary"
    }

    public var configurationName: String { providerKey }
    public var type: String { role }
    public var displayName: String { appName.isEmpty ? name : appName }
}

/// A user-facing integration connection returned by `GET /connections`.
/// Unlike runtime connections, this includes the catalog logo used by the
/// dashboard and agent capability picker.
public struct AptevaConnection: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let appSlug: String
    public let appName: String
    public let name: String
    public let status: String
    public let source: String
    public let projectID: String?
    public let logo: String
    public let toolCount: Int

    public enum CodingKeys: String, CodingKey {
        case id, name, status, source, logo
        case appSlug = "app_slug"
        case appName = "app_name"
        case projectID = "project_id"
        case toolCount = "tool_count"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        appSlug = try values.decodeIfPresent(String.self, forKey: .appSlug) ?? ""
        appName = try values.decodeIfPresent(String.self, forKey: .appName) ?? appSlug
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? appName
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? ""
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? ""
        projectID = try values.decodeIfPresent(String.self, forKey: .projectID)
        logo = try values.decodeIfPresent(String.self, forKey: .logo) ?? ""
        toolCount = try values.decodeIfPresent(Int.self, forKey: .toolCount) ?? 0
    }
}

public struct AptevaMCPServer: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let command: String
    public let arguments: String
    public let description: String
    public let status: String
    public let toolCount: Int
    public let source: String
    public let transport: String?
    public let url: String?
    public let connectionID: Int64?
    public let createdVia: String?
    public let ownerAppInstallID: Int64?
    public let projectID: String?
    public let proxyConfiguration: AptevaMCPProxyConfiguration?

    public enum CodingKeys: String, CodingKey {
        case id, name, command, description, status, source, transport, url
        case arguments = "args"
        case toolCount = "tool_count"
        case connectionID = "connection_id"
        case createdVia = "created_via"
        case ownerAppInstallID = "owner_app_install_id"
        case projectID = "project_id"
        case proxyConfiguration = "proxy_config"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int64.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        command = try values.decodeIfPresent(String.self, forKey: .command) ?? ""
        arguments = try values.decodeIfPresent(String.self, forKey: .arguments) ?? ""
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        status = try values.decode(String.self, forKey: .status)
        toolCount = try values.decodeIfPresent(Int.self, forKey: .toolCount) ?? 0
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? ""
        transport = try values.decodeIfPresent(String.self, forKey: .transport)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        connectionID = try values.decodeIfPresent(Int64.self, forKey: .connectionID)
        createdVia = try values.decodeIfPresent(String.self, forKey: .createdVia)
        ownerAppInstallID = try values.decodeIfPresent(Int64.self, forKey: .ownerAppInstallID)
        projectID = try values.decodeIfPresent(String.self, forKey: .projectID)
        proxyConfiguration = try values.decodeIfPresent(AptevaMCPProxyConfiguration.self, forKey: .proxyConfiguration)
    }

    public var attachmentName: String { proxyConfiguration?.name ?? name }
    public var displayName: String { description.isEmpty ? name : description }
    public var isAvailable: Bool {
        ["running", "reachable", "recovering"].contains(status)
            && (proxyConfiguration != nil || url?.isEmpty == false || !command.isEmpty)
    }
}

public struct AptevaMCPProxyConfiguration: Decodable, Hashable, Sendable {
    public let name: String
    public let transport: String
    public let url: String?
    public let command: String?
    public let arguments: [String]?

    public enum CodingKeys: String, CodingKey {
        case name, transport, url, command
        case arguments = "args"
    }
}

public struct AptevaAgentChatMessage: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let role: String
    public let text: String
    public let time: Date
    public let toolName: String?
    public let toolDone: Bool?
    public let toolDurationMs: Int64?
    public let toolSuccess: Bool?

    public enum CodingKeys: String, CodingKey {
        case id, role, text
        case time
        case toolName = "tool_name"
        case toolDone = "tool_done"
        case toolDurationMs = "tool_duration_ms"
        case toolSuccess = "tool_success"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        role = try values.decode(String.self, forKey: .role)
        text = try values.decodeIfPresent(String.self, forKey: .text) ?? ""
        time = parseAptevaDate(try values.decode(String.self, forKey: .time)) ?? .distantPast
        toolName = try values.decodeIfPresent(String.self, forKey: .toolName)
        toolDone = try values.decodeIfPresent(Bool.self, forKey: .toolDone)
        toolDurationMs = try values.decodeIfPresent(Int64.self, forKey: .toolDurationMs)
        toolSuccess = try values.decodeIfPresent(Bool.self, forKey: .toolSuccess)
    }
}

public struct AptevaAgentStats: Decodable, Sendable {
    public let instanceID: Int64
    public let name: String
    public let status: String
    public let llmCalls: Int
    public let tokensIn: Int
    public let tokensOut: Int
    public let cost: Double
    public let errors: Int
    public let toolCalls: Int

    public enum CodingKeys: String, CodingKey {
        case instanceID = "instance_id"
        case name, status
        case llmCalls = "llm_calls"
        case tokensIn = "tokens_in"
        case tokensOut = "tokens_out"
        case cost, errors
        case toolCalls = "tool_calls"
    }
}

public struct AptevaTelemetryEvent: Decodable, Identifiable, Sendable {
    public let id: String
    public let instanceID: Int64
    public let threadID: String
    public let type: String
    public let time: Date
    public let data: [String: JSONValue]

    public enum CodingKeys: String, CodingKey {
        case id
        case instanceID = "instance_id"
        case threadID = "thread_id"
        case type, time, data
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        instanceID = try values.decode(Int64.self, forKey: .instanceID)
        threadID = try values.decodeIfPresent(String.self, forKey: .threadID) ?? ""
        type = try values.decode(String.self, forKey: .type)
        let rawTime = try values.decode(String.self, forKey: .time)
        time = parseAptevaDate(rawTime) ?? .distantPast
        data = try values.decodeIfPresent([String: JSONValue].self, forKey: .data) ?? [:]
    }
}

public enum JSONValue: Decodable, Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let object = try? value.decode([String: JSONValue].self) { self = .object(object) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .null }
    }

    public var stringValue: String? {
        switch self {
        case let .string(value): value
        case let .number(value): value.formatted(.number.precision(.fractionLength(0...2)))
        case let .bool(value): value ? "true" : "false"
        default: nil
        }
    }

    public var intValue: Int? {
        if case let .number(value) = self { return Int(value) }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public var compactDescription: String {
        switch self {
        case let .string(value): value
        case let .number(value): value.formatted(.number.precision(.fractionLength(0...2)))
        case let .bool(value): value ? "true" : "false"
        case let .object(value):
            value.prefix(3).map { "\($0.key)=\($0.value.compactDescription)" }.joined(separator: ", ")
        case let .array(value): value.prefix(3).map(\.compactDescription).joined(separator: ", ")
        case .null: ""
        }
    }
}

public struct AptevaChatComponent: Decodable, Sendable {
    public let app: String
    public let name: String
    public let props: [String: JSONValue]?
}

public struct AptevaChatMessage: Decodable, Sendable {
    public let id: Int64
    public let content: String
    public let createdAt: String
    public let components: [AptevaChatComponent]?

    public enum CodingKeys: String, CodingKey {
        case id, content, components
        case createdAt = "created_at"
    }
}

public struct AptevaApprovalMessage: Decodable, Sendable {
    public let message: AptevaChatMessage
    public let instanceID: Int64
    public let instanceName: String
    public let projectID: String
    public let title: String
    public let body: String
    public let status: String

    public enum CodingKeys: String, CodingKey {
        case message, title, body, status
        case instanceID = "instance_id"
        case instanceName = "instance_name"
        case projectID = "project_id"
    }
}

public struct AptevaReportMessage: Decodable, Sendable {
    public let message: AptevaChatMessage
    public let instanceID: Int64
    public let instanceName: String
    public let projectID: String
    public let title: String
    public let summary: String
    public let period: String?

    public enum CodingKeys: String, CodingKey {
        case message, title, summary, period
        case instanceID = "instance_id"
        case instanceName = "instance_name"
        case projectID = "project_id"
    }
}

public struct AptevaAlertMessage: Decodable, Sendable {
    public let message: AptevaChatMessage
    public let instanceID: Int64
    public let instanceName: String
    public let projectID: String
    public let title: String
    public let body: String
    public let severity: String

    public enum CodingKeys: String, CodingKey {
        case message, title, body, severity
        case instanceID = "instance_id"
        case instanceName = "instance_name"
        case projectID = "project_id"
    }
}

public enum AptevaInboxKind: String, Sendable {
    case approval, report, alert
}

public struct AptevaInboxAction: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let style: String
}

public struct AptevaInboxItem: Identifiable, Hashable, Sendable {
    public let kind: AptevaInboxKind
    public let messageID: Int64
    public let instanceID: Int64
    public let instanceName: String
    public let title: String
    public let body: String
    public let meta: String
    public let createdAt: Date
    public let actions: [AptevaInboxAction]

    public var id: String { "\(kind.rawValue)-\(messageID)" }
}

public struct DashboardActivityItem: Identifiable, Hashable, Sendable {
    public enum Category: Sendable { case tool, memory, thought, thread, channel, error }

    public let id: String
    public let agentName: String
    public let title: String
    public let detail: String?
    public let time: Date
    public let category: Category

    public init(id: String, agentName: String, title: String, detail: String?, time: Date, category: Category) {
        self.id = id
        self.agentName = agentName
        self.title = title
        self.detail = detail
        self.time = time
        self.category = category
    }
}

public struct DashboardTotals: Sendable {
    public let runningAgents: Int
    public let totalAgents: Int
    public let llmCalls: Int
    public let toolCalls: Int
    public let tokens: Int
    public let cost: Double
    public let errors: Int

    public init(runningAgents: Int, totalAgents: Int, llmCalls: Int, toolCalls: Int, tokens: Int, cost: Double, errors: Int) {
        self.runningAgents = runningAgents
        self.totalAgents = totalAgents
        self.llmCalls = llmCalls
        self.toolCalls = toolCalls
        self.tokens = tokens
        self.cost = cost
        self.errors = errors
    }

    public static let empty = DashboardTotals(runningAgents: 0, totalAgents: 0, llmCalls: 0, toolCalls: 0, tokens: 0, cost: 0, errors: 0)
}

public struct AptevaDashboardWidgetSurface: Decodable, Sendable {
    public let surface: String
    public let projectID: String
    public let revision: Int64
    public var layout: [AptevaDashboardWidgetInstance]
    public let definitions: [AptevaDashboardWidgetDefinition]

    public init(surface: String, projectID: String, revision: Int64, layout: [AptevaDashboardWidgetInstance], definitions: [AptevaDashboardWidgetDefinition]) {
        self.surface = surface
        self.projectID = projectID
        self.revision = revision
        self.layout = layout
        self.definitions = definitions
    }

    public enum CodingKeys: String, CodingKey {
        case surface, revision, layout, definitions
        case projectID = "project_id"
    }
}

public struct AptevaDashboardWidgetInstance: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let component: String
    public var size: String
    public var settings: [String: NativeJSONValue]

    public enum CodingKeys: String, CodingKey { case id, component, size, settings }

    public init(id: String, component: String, size: String, settings: [String: NativeJSONValue] = [:]) {
        self.id = id
        self.component = component
        self.size = size
        self.settings = settings
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        component = try values.decode(String.self, forKey: .component)
        size = try values.decodeIfPresent(String.self, forKey: .size) ?? "half"
        settings = try values.decodeIfPresent([String: NativeJSONValue].self, forKey: .settings) ?? [:]
    }
}

public struct AptevaDashboardWidgetDefinition: Decodable, Identifiable, Sendable {
    public let component: String
    public let kind: String
    public let app: String?
    public let installID: Int64?
    public let label: String
    public let description: String?
    public let icon: String?
    public let iconStyle: String?
    public let supportedSizes: [String]
    public let defaultSize: String
    public let defaultSettings: [String: NativeJSONValue]
    public let settingsSchema: [String: NativeJSONValue]
    public let refreshTopics: [String]
    public let suggested: Bool
    public let native: AptevaDashboardNativeRenderer?
    public let projectSurfaces: [AptevaNativeSurfaceDescriptor]

    public var id: String { component }

    public enum CodingKeys: String, CodingKey {
        case component, kind, app, label, description, icon, suggested, native
        case installID = "install_id"
        case iconStyle = "icon_style"
        case supportedSizes = "supported_sizes"
        case defaultSize = "default_size"
        case defaultSettings = "default_settings"
        case settingsSchema = "settings_schema"
        case refreshTopics = "refresh_topics"
        case projectSurfaces = "project_surfaces"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        component = try values.decode(String.self, forKey: .component)
        kind = try values.decode(String.self, forKey: .kind)
        app = try values.decodeIfPresent(String.self, forKey: .app)
        installID = try values.decodeIfPresent(Int64.self, forKey: .installID)
        label = try values.decode(String.self, forKey: .label)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        iconStyle = try values.decodeIfPresent(String.self, forKey: .iconStyle)
        supportedSizes = try values.decodeIfPresent([String].self, forKey: .supportedSizes) ?? ["half"]
        defaultSize = try values.decodeIfPresent(String.self, forKey: .defaultSize) ?? supportedSizes.first ?? "half"
        defaultSettings = try values.decodeIfPresent([String: NativeJSONValue].self, forKey: .defaultSettings) ?? [:]
        settingsSchema = try values.decodeIfPresent([String: NativeJSONValue].self, forKey: .settingsSchema) ?? [:]
        refreshTopics = try values.decodeIfPresent([String].self, forKey: .refreshTopics) ?? []
        suggested = try values.decodeIfPresent(Bool.self, forKey: .suggested) ?? false
        native = try values.decodeIfPresent(AptevaDashboardNativeRenderer.self, forKey: .native)
        projectSurfaces = try values.decodeIfPresent([AptevaNativeSurfaceDescriptor].self, forKey: .projectSurfaces) ?? []
    }
}

public struct AptevaDashboardNativeRenderer: Decodable, Sendable {
    public let schema: String
    public let entry: String
}

public struct AptevaDashboardLayoutPatchResponse: Decodable, Sendable {
    public let value: [AptevaDashboardWidgetInstance]
    public let revision: Int64
}

public struct AptevaDashboardLayoutPatchRequest: Encodable, Sendable {
    public let value: [AptevaDashboardWidgetInstance]
}

public struct AptevaAppEventEnvelope: Decodable, Sendable {
    public let topic: String
    public let app: String
    public let projectID: String
    public let installID: Int64?
    public let sequence: Int64?
    public let time: String?
    public let data: NativeJSONValue?

    public enum CodingKeys: String, CodingKey {
        case topic, app, time, data
        case projectID = "project_id"
        case installID = "install_id"
        case sequence = "seq"
    }
}

public func parseAptevaDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }

    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    if let date = basic.date(from: value) { return date }

    let normalized = value.contains("T") ? value : value.replacingOccurrences(of: " ", with: "T") + "Z"
    return basic.date(from: normalized)
}
