import Foundation

public struct AptevaInstalledApp: Decodable, Identifiable, Hashable, Sendable {
    public let installID: Int64
    public let appID: Int64
    public let name: String
    public let displayName: String
    public let version: String
    public let availableVersion: String?
    public let description: String
    public let icon: String
    public let projectID: String
    public let status: String
    public let statusMessage: String?
    public let errorMessage: String?
    public let source: String
    public let upgradePolicy: String
    public let deprecated: Bool
    public let deprecation: String?
    public let surfaces: AptevaAppSurfaceSummary?
    public let uiSurfaces: [AptevaNativeSurfaceDescriptor]

    public var id: Int64 { installID }
    public var updateAvailable: Bool {
        guard !deprecated, let availableVersion, !availableVersion.isEmpty else { return false }
        return availableVersion != version
    }
    public var isLifecycleManaged: Bool { source != "builtin" && source != "integration" }

    public enum CodingKeys: String, CodingKey {
        case installID = "install_id"
        case appID = "app_id"
        case name
        case displayName = "display_name"
        case version
        case availableVersion = "available_version"
        case description, icon
        case projectID = "project_id"
        case status
        case statusMessage = "status_message"
        case errorMessage = "error_message"
        case source
        case upgradePolicy = "upgrade_policy"
        case deprecated, deprecation, surfaces
        case uiSurfaces = "ui_surfaces"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        installID = try values.decode(Int64.self, forKey: .installID)
        appID = try values.decode(Int64.self, forKey: .appID)
        name = try values.decode(String.self, forKey: .name)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? name
        version = try values.decode(String.self, forKey: .version)
        availableVersion = try values.decodeIfPresent(String.self, forKey: .availableVersion)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        icon = try values.decodeIfPresent(String.self, forKey: .icon) ?? ""
        projectID = try values.decode(String.self, forKey: .projectID)
        status = try values.decode(String.self, forKey: .status)
        statusMessage = try values.decodeIfPresent(String.self, forKey: .statusMessage)
        errorMessage = try values.decodeIfPresent(String.self, forKey: .errorMessage)
        source = try values.decode(String.self, forKey: .source)
        upgradePolicy = try values.decode(String.self, forKey: .upgradePolicy)
        deprecated = try values.decodeIfPresent(Bool.self, forKey: .deprecated) ?? false
        deprecation = try values.decodeIfPresent(String.self, forKey: .deprecation)
        surfaces = try values.decodeIfPresent(AptevaAppSurfaceSummary.self, forKey: .surfaces)
        uiSurfaces = try values.decodeIfPresent([AptevaNativeSurfaceDescriptor].self, forKey: .uiSurfaces) ?? []
    }
}

public struct AptevaNativeSurfaceDescriptor: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let icon: String
    public let schema: String
    public let entry: String
    public let slots: [String]

    public var supportsProjectApp: Bool {
        schema == "apteva-native-surface/v1" && slots.contains("mobile.project_app")
    }
}

public struct AptevaAppSurfaceSummary: Decodable, Hashable, Sendable {
    public let kind: String?
    public let mcpToolCount: Int
    public let skillCount: Int
    public let httpRouteCount: Int
    public let uiPanelCount: Int
    public let channelCount: Int
    public let workerCount: Int

    public enum CodingKeys: String, CodingKey {
        case kind
        case mcpToolCount = "mcp_tool_count"
        case skillCount = "skill_count"
        case httpRouteCount = "http_route_count"
        case uiPanelCount = "ui_panel_count"
        case channelCount = "channel_count"
        case workerCount = "worker_count"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decodeIfPresent(String.self, forKey: .kind)
        mcpToolCount = try values.decodeIfPresent(Int.self, forKey: .mcpToolCount) ?? 0
        skillCount = try values.decodeIfPresent(Int.self, forKey: .skillCount) ?? 0
        httpRouteCount = try values.decodeIfPresent(Int.self, forKey: .httpRouteCount) ?? 0
        uiPanelCount = try values.decodeIfPresent(Int.self, forKey: .uiPanelCount) ?? 0
        channelCount = try values.decodeIfPresent(Int.self, forKey: .channelCount) ?? 0
        workerCount = try values.decodeIfPresent(Int.self, forKey: .workerCount) ?? 0
    }
}

public struct AptevaMarketplaceResponse: Decodable, Sendable {
    public let registryURL: String
    public let apps: [AptevaMarketplaceApp]
    public let total: Int?
    public let categories: [String: Int]?

    public enum CodingKeys: String, CodingKey {
        case registryURL = "registry_url"
        case apps, total, categories
    }
}

public struct AptevaMarketplaceApp: Decodable, Identifiable, Hashable, Sendable {
    public let name: String
    public let displayName: String
    public let version: String
    public let description: String
    public let author: String
    public let repo: String
    public let manifestURL: String
    public let icon: String
    public let tags: [String]
    public let official: Bool
    public let category: String
    public let installed: Bool
    public let builtin: Bool
    public let deprecated: Bool
    public let deprecation: String?
    public let surfaces: AptevaAppSurfaceSummary?

    public var id: String { name }

    public enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case version, description, author, repo
        case manifestURL = "manifest_url"
        case icon, tags, official, category, installed, builtin, deprecated, deprecation, surfaces
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? name
        version = try values.decode(String.self, forKey: .version)
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try values.decodeIfPresent(String.self, forKey: .author) ?? ""
        repo = try values.decodeIfPresent(String.self, forKey: .repo) ?? ""
        manifestURL = try values.decodeIfPresent(String.self, forKey: .manifestURL) ?? ""
        icon = try values.decodeIfPresent(String.self, forKey: .icon) ?? ""
        tags = try values.decodeIfPresent([String].self, forKey: .tags) ?? []
        official = try values.decode(Bool.self, forKey: .official)
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? ""
        installed = try values.decode(Bool.self, forKey: .installed)
        builtin = try values.decode(Bool.self, forKey: .builtin)
        deprecated = try values.decodeIfPresent(Bool.self, forKey: .deprecated) ?? false
        deprecation = try values.decodeIfPresent(String.self, forKey: .deprecation)
        surfaces = try values.decodeIfPresent(AptevaAppSurfaceSummary.self, forKey: .surfaces)
    }
}

public struct AptevaAppPreflight: Decodable, Sendable {
    public let manifest: AptevaAppInstallManifest
    public let roles: [AptevaAppInstallRole]
}

public struct AptevaAppInstallManifest: Decodable, Sendable {
    public let name: String
    public let displayName: String
    public let version: String
    public let description: String
    public let icon: String?
    public let scopes: [String]
    public let configSchema: [AptevaAppConfigField]

    public enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case version, description, icon, scopes
        case configSchema = "config_schema"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? name
        version = try values.decodeIfPresent(String.self, forKey: .version) ?? ""
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        icon = try values.decodeIfPresent(String.self, forKey: .icon)
        scopes = try values.decodeIfPresent([String].self, forKey: .scopes) ?? ["project"]
        configSchema = try values.decodeIfPresent([AptevaAppConfigField].self, forKey: .configSchema) ?? []
    }
}

public struct AptevaAppConfigField: Decodable, Identifiable, Hashable, Sendable {
    public let name: String
    public let label: String?
    public let type: String?
    public let description: String?
    public let required: Bool
    public let defaultValue: String?
    public let options: [String]
    public let requiredIfRoleBound: String?

    public var id: String { name }

    public enum CodingKeys: String, CodingKey {
        case name, label, type, description, required, options
        case defaultValue = "default"
        case requiredIfRoleBound = "required_if_role_bound"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        type = try values.decodeIfPresent(String.self, forKey: .type)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        required = try values.decodeIfPresent(Bool.self, forKey: .required) ?? false
        options = try values.decodeIfPresent([String].self, forKey: .options) ?? []
        requiredIfRoleBound = try values.decodeIfPresent(String.self, forKey: .requiredIfRoleBound)
        if let string = try? values.decodeIfPresent(String.self, forKey: .defaultValue) {
            defaultValue = string
        } else if let boolean = try? values.decodeIfPresent(Bool.self, forKey: .defaultValue) {
            defaultValue = String(boolean)
        } else if let number = try? values.decodeIfPresent(Double.self, forKey: .defaultValue) {
            defaultValue = String(number)
        } else {
            defaultValue = nil
        }
    }
}

public struct AptevaAppInstallRole: Decodable, Identifiable, Hashable, Sendable {
    public let role: String
    public let kind: String
    public let mode: String?
    public let label: String?
    public let required: Bool
    public let hint: String?
    public let integrationCandidates: [AptevaIntegrationCandidate]
    public let appCandidates: [AptevaAppCandidate]

    public var id: String { role }

    public enum CodingKeys: String, CodingKey {
        case role, kind, mode, label, required, hint
        case integrationCandidates = "integration_candidates"
        case appCandidates = "app_candidates"
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = try values.decode(String.self, forKey: .role)
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? "integration"
        mode = try values.decodeIfPresent(String.self, forKey: .mode)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        required = try values.decodeIfPresent(Bool.self, forKey: .required) ?? false
        hint = try values.decodeIfPresent(String.self, forKey: .hint)
        integrationCandidates = try values.decodeIfPresent([AptevaIntegrationCandidate].self, forKey: .integrationCandidates) ?? []
        appCandidates = try values.decodeIfPresent([AptevaAppCandidate].self, forKey: .appCandidates) ?? []
    }
}

public struct AptevaIntegrationCandidate: Decodable, Identifiable, Hashable, Sendable {
    public let connectionID: Int64
    public let appSlug: String
    public let name: String
    public let status: String
    public let scope: String?

    public var id: Int64 { connectionID }

    public enum CodingKeys: String, CodingKey {
        case connectionID = "connection_id"
        case appSlug = "app_slug"
        case name, status, scope
    }
}

public struct AptevaAppCandidate: Decodable, Identifiable, Hashable, Sendable {
    public let installID: Int64
    public let appName: String
    public let displayName: String

    public var id: Int64 { installID }

    public enum CodingKeys: String, CodingKey {
        case installID = "install_id"
        case appName = "app_name"
        case displayName = "display_name"
    }
}

public enum AptevaAppBinding: Encodable, Sendable {
    case single(Int64)
    case multiple(ids: [Int64], defaultID: Int64?)
    case none

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .single(let id):
            var value = encoder.singleValueContainer()
            try value.encode(id)
        case .multiple(let ids, let defaultID):
            var value = encoder.container(keyedBy: MultipleKeys.self)
            try value.encode(ids, forKey: .ids)
            try value.encodeIfPresent(defaultID, forKey: .defaultID)
        case .none:
            var value = encoder.singleValueContainer()
            try value.encodeNil()
        }
    }

    private enum MultipleKeys: String, CodingKey {
        case ids
        case defaultID = "default_id"
    }
}

public struct AptevaAppInstallResult: Decodable, Sendable {
    public let installID: Int64
    public let appID: Int64
    public let status: String
    public let nextStep: String?
    public let error: String?

    public enum CodingKeys: String, CodingKey {
        case installID = "install_id"
        case appID = "app_id"
        case status
        case nextStep = "next_step"
        case error
    }
}

public struct AptevaAppLifecycleResult: Decodable, Sendable {
    public let status: String
    public let version: String?
}
