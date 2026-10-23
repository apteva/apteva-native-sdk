import Foundation

public struct AptevaAuthStatus: Decodable, Sendable {
    public let regMode: String
    public let needsSetup: Bool

    public enum CodingKeys: String, CodingKey {
        case regMode = "reg_mode"
        case needsSetup = "needs_setup"
    }
}

public struct AptevaUser: Codable, Sendable {
    public let userID: Int64
    public let email: String
    public let role: String?

    public enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email, role
    }
}

public struct AptevaProject: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let color: String
}

public struct AptevaCreatedAPIKey: Decodable, Sendable {
    public let id: Int64
    public let name: String
    public let key: String
    public let prefix: String
    public let kind: String
}

public enum AptevaAPIError: LocalizedError, Sendable {
    case invalidServerURL
    case unsupportedScheme
    case setupRequired
    case invalidCredentials
    case server(status: Int, message: String)
    case invalidResponse
    case connection(String)

    public var isUnauthorized: Bool {
        if case let .server(status, _) = self {
            return status == 401
        }
        return false
    }

    public var isConnectionFailure: Bool {
        if case .connection = self {
            return true
        }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "Enter a valid server address."
        case .unsupportedScheme:
            "The server address must use HTTPS."
        case .setupRequired:
            "This instance needs first-time setup in its web dashboard."
        case .invalidCredentials:
            "The username or password is incorrect."
        case let .server(_, message):
            message
        case .invalidResponse:
            "This does not appear to be a compatible Apteva instance."
        case let .connection(message):
            message
        }
    }
}

public struct AptevaAPIClient: Sendable {
    public let baseURL: URL
    private let bearerToken: String?
    private let session: URLSession
    private let sseTransport: AptevaSSETransport

    public init(
        baseURL: URL,
        bearerToken: String? = nil,
        protocolClasses: [AnyClass]? = nil
    ) {
        self.baseURL = baseURL
        self.bearerToken = bearerToken
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        session = URLSession(configuration: configuration)
        sseTransport = AptevaSSETransport(
            baseURL: baseURL,
            bearerToken: bearerToken,
            protocolClasses: protocolClasses
        )
    }

    public static func normalizedServerURL(from input: String) throws -> URL {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw AptevaAPIError.invalidServerURL }
        if !value.contains("://") {
            value = "https://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let url = components.url else {
            throw AptevaAPIError.invalidServerURL
        }
        guard scheme == "https" else {
            throw AptevaAPIError.unsupportedScheme
        }
        return url
    }

    public static func clearCookies(for baseURL: URL) {
        HTTPCookieStorage.shared.cookies(for: baseURL)?.forEach {
            HTTPCookieStorage.shared.deleteCookie($0)
        }
    }

    public func authStatus() async throws -> AptevaAuthStatus {
        try await request("auth/status")
    }

    public func login(email: String, password: String) async throws -> AptevaUser {
        let body = try JSONEncoder().encode(LoginRequest(email: email, password: password))
        return try await request("auth/login", method: "POST", body: body)
    }

    public func currentUser() async throws -> AptevaUser {
        try await request("auth/me")
    }

    public func projects() async throws -> [AptevaProject] {
        try await request("projects")
    }

    public func createDeviceAPIKey(name: String) async throws -> AptevaCreatedAPIKey {
        let body = try JSONEncoder().encode(
            CreateAPIKeyRequest(
                name: name,
                kind: "private",
                rateLimitPerMinute: 600
            )
        )
        return try await request("auth/keys", method: "POST", body: body)
    }

    public func deleteAPIKey(id: Int64) async throws {
        let _: StatusResponse = try await request("auth/keys/\(id)", method: "DELETE")
    }

    public func logout() async throws {
        let _: StatusResponse = try await request("auth/logout", method: "POST")
    }

    public func mobilePushConfig() async throws -> AptevaMobilePushConfig {
        try await request("mobile/push/config")
    }

    public func mobilePushSubscriptions() async throws -> [AptevaMobilePushSubscription] {
        let response: AptevaMobilePushSubscriptionsResponse = try await request("mobile/push/subscriptions")
        return response.subscriptions
    }

    public func registerMobilePush(
        installationID: String,
        providerToken: String,
        bundleID: String,
        environment: String,
        appVersion: String,
        deviceName: String
    ) async throws -> AptevaMobilePushSubscription {
        let body = try JSONEncoder().encode(
            MobilePushRegistrationRequest(
                installationID: installationID,
                providerToken: providerToken,
                bundleID: bundleID,
                environment: environment,
                appVersion: appVersion,
                deviceName: deviceName
            )
        )
        let response: AptevaMobilePushSubscriptionResponse = try await request(
            "mobile/push/subscriptions",
            method: "POST",
            body: body
        )
        return response.subscription
    }

    public func deleteMobilePushSubscription(id: String) async throws {
        let _: AptevaMobilePushDeleteResponse = try await request(
            "mobile/push/subscriptions/\(queryValue(id))",
            method: "DELETE"
        )
    }

    public func testMobilePushSubscription(id: String) async throws {
        let _: AptevaMobilePushTestResponse = try await request(
            "mobile/push/subscriptions/\(queryValue(id))/test",
            method: "POST",
            body: Data("{}".utf8)
        )
    }

    public func agents(projectID: String) async throws -> [AptevaAgent] {
        try await request("agents?project_id=\(queryValue(projectID))")
    }

    public func agent(id: Int64) async throws -> AptevaAgent {
        try await request("agents/\(id)")
    }

    public func renameAgent(id: Int64, name: String) async throws -> AptevaAgent {
        let body = try JSONEncoder().encode(AgentRenameRequest(name: name))
        return try await request("agents/\(id)", method: "PUT", body: body)
    }

    public func agentConfiguration(id: Int64) async throws -> AptevaAgentConfiguration {
        try await request("agents/\(id)/config")
    }

    public func updateAgentConfiguration(
        id: Int64,
        directive: String?,
        mode: String,
        providers: [AptevaAgentProviderConfiguration]?
    ) async throws {
        let body = try JSONEncoder().encode(
            AgentConfigurationUpdateRequest(
                directive: directive,
                mode: mode,
                providers: providers
            )
        )
        let _: StatusResponse = try await request("agents/\(id)/config", method: "PUT", body: body)
    }

    public func runtimeConnections(projectID: String) async throws -> [AptevaRuntimeConnection] {
        try await request("connections/runtime?project_id=\(queryValue(projectID))")
    }

    public func connections(projectID: String) async throws -> [AptevaConnection] {
        try await request("connections?project_id=\(queryValue(projectID))")
    }

    public func mcpServers(projectID: String) async throws -> [AptevaMCPServer] {
        try await request("mcp-servers?project_id=\(queryValue(projectID))")
    }

    public func mutateAgentMCPServers(id: Int64, serverIDs: [Int64], action: String) async throws {
        let body = try JSONEncoder().encode(
            AgentMCPMutationRequest(action: action, serverIDs: serverIDs)
        )
        let _: StatusResponse = try await request("agents/\(id)/mcp-servers", method: "POST", body: body)
    }

    public func startAgent(id: Int64) async throws -> AptevaAgent {
        try await request("agents/\(id)/start", method: "POST")
    }

    public func stopAgent(id: Int64) async throws -> AptevaAgent {
        try await request("agents/\(id)/stop", method: "POST")
    }

    public func sendAgentEvent(id: Int64, message: String) async throws {
        let body = try JSONEncoder().encode(AgentEventRequest(message: message))
        let _: AgentEventResponse = try await request("agents/\(id)/event", method: "POST", body: body)
    }

    public func agentChatHistory(id: Int64, limit: Int = 50) async throws -> [AptevaAgentChatMessage] {
        try await request("agents/\(id)/chat-history?limit=\(min(max(limit, 1), 200))")
    }

    public func projectStats(projectID: String) async throws -> [AptevaAgentStats] {
        try await request("telemetry/project-stats?project_id=\(queryValue(projectID))&period=24h")
    }

    public func telemetry(
        agentID: Int64,
        type: String? = nil,
        limit: Int = 12,
        since: Date? = nil,
        threadID: String? = nil
    ) async throws -> [AptevaTelemetryEvent] {
        var path = "telemetry?agent_id=\(agentID)&limit=\(min(max(limit, 1), 1000))"
        if let type, !type.isEmpty {
            path += "&type=\(queryValue(type))"
        }
        if let since {
            path += "&since=\(queryValue(ISO8601DateFormatter().string(from: since)))"
        }
        if let threadID, !threadID.isEmpty {
            path += "&thread_id=\(queryValue(threadID))"
        }
        return try await request(path)
    }

    public func dashboardInbox(projectID: String, limit: Int = 12) async throws -> [AptevaInboxItem] {
        let project = queryValue(projectID)
        async let approvals: [AptevaApprovalMessage] = request("apps/channel-chat/approval-messages?project_id=\(project)&status=pending&limit=\(limit)")
        async let reports: [AptevaReportMessage] = request("apps/channel-chat/report-messages?project_id=\(project)&limit=\(limit)")
        async let alerts: [AptevaAlertMessage] = request("apps/channel-chat/alert-messages?project_id=\(project)&limit=\(limit)")
        let (approvalRows, reportRows, alertRows) = try await (approvals, reports, alerts)

        var items = approvalRows.map(AptevaInboxItem.init)
        items.append(contentsOf: reportRows.map(AptevaInboxItem.init))
        items.append(contentsOf: alertRows.map(AptevaInboxItem.init))
        return items.sorted { $0.messageID > $1.messageID }.prefix(limit).map { $0 }
    }

    public func currentStatuses(projectID: String) async throws -> [AptevaCurrentStatus] {
        try await request("apps/channel-chat/current-statuses?project_id=\(queryValue(projectID))")
    }

    public func conversations(projectID: String) async throws -> [AptevaConversation] {
        try await request("apps/channel-chat/conversations?project_id=\(queryValue(projectID))")
    }

    public func conversations(agentID: Int64) async throws -> [AptevaConversation] {
        let rows: [AptevaConversation] = try await request("apps/channel-chat/chats?instance_id=\(agentID)")
        return rows.filter { !$0.id.hasPrefix("default-") }
    }

    public func createConversation(
        projectID: String,
        agentIDs: [Int64],
        title: String? = nil,
        leadAgentID: Int64? = nil
    ) async throws -> AptevaConversation {
        let body = try JSONEncoder().encode(
            CreateConversationRequest(
                projectID: projectID,
                agentIDs: agentIDs,
                title: title,
                leadAgentID: leadAgentID
            )
        )
        return try await request("apps/channel-chat/conversations", method: "POST", body: body)
    }

    public func conversationMessages(
        chatID: String,
        since: Int64 = 0,
        limit: Int = 500
    ) async throws -> [AptevaConversationMessage] {
        try await request(
            "apps/channel-chat/messages?chat_id=\(queryValue(chatID))&since=\(since)&limit=\(min(max(limit, 1), 1000))"
        )
    }

    public func sendConversationMessage(
        chatID: String,
        content: String,
        attachments: [AptevaConversationAttachment] = [],
        clientMessageID: String = UUID().uuidString.lowercased()
    ) async throws -> AptevaConversationMessage {
        let body = try JSONEncoder().encode(
            PostConversationMessageRequest(
                content: content,
                attachments: attachments.isEmpty ? nil : attachments,
                clientMessageID: clientMessageID
            )
        )
        return try await request(
            "apps/channel-chat/messages?chat_id=\(queryValue(chatID))",
            method: "POST",
            body: body
        )
    }

    public func unreadConversations() async throws -> [AptevaUnreadConversation] {
        try await request("apps/channel-chat/unread-summary")
    }

    /// The unread endpoint is user-wide. Native project surfaces must scope it
    /// against the real conversation collection instead of showing an account
    /// total beside a project-only list.
    public func unreadConversations(projectID: String) async throws -> [AptevaUnreadConversation] {
        async let unreadRequest: [AptevaUnreadConversation] = unreadConversations()
        async let conversationRequest: [AptevaConversation] = conversations(projectID: projectID)
        let (unread, conversations) = try await (unreadRequest, conversationRequest)
        let projectConversationIDs = Set(conversations.map(\.id))
        return unread.filter { projectConversationIDs.contains($0.chatID) }
    }

    public func markConversationSeen(chatID: String, lastSeenID: Int64) async throws {
        let body = try JSONEncoder().encode(
            ConversationSeenRequest(chatID: chatID, lastSeenID: lastSeenID)
        )
        let _: ConversationSeenResponse = try await request(
            "apps/channel-chat/seen",
            method: "POST",
            body: body
        )
    }

    public func updateConversationPresence(chatID: String, connected: Bool) async throws {
        let body = try JSONEncoder().encode(
            ConversationPresenceRequest(
                chatID: chatID,
                action: connected ? "connected" : "disconnected"
            )
        )
        let _: StatusResponse = try await request(
            "apps/channel-chat/presence",
            method: "POST",
            body: body
        )
    }

    public func eventStream(_ path: String) -> AsyncThrowingStream<AptevaSSEEvent, Error> {
        sseTransport.events(path: path)
    }

    public func performInboxAction(messageID: Int64, actionID: String) async throws {
        let body = try JSONEncoder().encode(InboxActionRequest(messageID: messageID, actionID: actionID))
        let _: InboxActionResponse = try await request("apps/channel-chat/message-action", method: "POST", body: body)
    }

    public func dismissInboxMessage(messageID: Int64) async throws {
        let body = try JSONEncoder().encode(InboxDismissRequest(messageID: messageID))
        let _: InboxDismissResponse = try await request("apps/channel-chat/message-dismiss", method: "POST", body: body)
    }

    public func installedApps(projectID: String) async throws -> [AptevaInstalledApp] {
        try await request("apps?project_id=\(queryValue(projectID))")
    }

    /// A single mobile navigation favourite, independent of the desktop sidebar.
    public func mobileFavouriteApp(projectID: String) async throws -> AptevaMobileFavouritePreference {
        try await request("ui-layout/projects/\(queryValue(projectID))/surfaces/navigation.mobile-favourite")
    }

    /// Updates only this surface; concurrent layout edits are protected by revision.
    public func updateMobileFavouriteApp(
        projectID: String, appName: String?, revision: Int64
    ) async throws -> AptevaMobileFavouritePreference {
        let body = try JSONEncoder().encode(MobileFavouritePatch(value: appName.map { [$0] } ?? []))
        return try await request(
            "ui-layout/projects/\(queryValue(projectID))/surfaces/navigation.mobile-favourite",
            method: "PATCH", body: body,
            headers: ["If-Match": "\"\(revision)\""]
        )
    }

    public func dashboardWidgetSurface(projectID: String) async throws -> AptevaDashboardWidgetSurface {
        try await request("ui/surfaces/dashboard.home?project_id=\(queryValue(projectID))")
    }

    public func updateDashboardWidgetLayout(
        projectID: String,
        layout: [AptevaDashboardWidgetInstance],
        revision: Int64
    ) async throws -> AptevaDashboardLayoutPatchResponse {
        let body = try JSONEncoder().encode(AptevaDashboardLayoutPatchRequest(value: layout))
        return try await request(
            "ui-layout/projects/\(queryValue(projectID))/surfaces/dashboard.home",
            method: "PATCH",
            body: body,
            headers: ["If-Match": "\"\(revision)\""]
        )
    }

    public func marketplaceApps(projectID: String, query: String = "") async throws -> AptevaMarketplaceResponse {
        var path = "apps/marketplace?project_id=\(queryValue(projectID))&page_size=100"
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            path += "&q=\(queryValue(query))"
        }
        return try await request(path)
    }

    public func preflightApp(manifestURL: String, projectID: String) async throws -> AptevaAppPreflight {
        let body = try JSONEncoder().encode(AppPreflightRequest(manifestURL: manifestURL, projectID: projectID))
        return try await request("apps/install/preflight", method: "POST", body: body)
    }

    public func installApp(
        manifestURL: String,
        projectID: String,
        config: [String: String],
        bindings: [String: AptevaAppBinding]
    ) async throws -> AptevaAppInstallResult {
        let body = try JSONEncoder().encode(
            AppInstallRequest(
                manifestURL: manifestURL,
                projectID: projectID,
                config: config,
                upgradePolicy: "manual",
                bindings: bindings
            )
        )
        return try await request("apps/install", method: "POST", body: body)
    }

    public func upgradeApp(installID: Int64, approveNewPermissions: Bool = false) async throws -> AptevaAppLifecycleResult {
        let body = try JSONEncoder().encode(AppUpgradeRequest(approveNewPermissions: approveNewPermissions))
        return try await request("apps/installs/\(installID)/upgrade", method: "POST", body: body)
    }

    public func setAppStatus(installID: Int64, status: String) async throws -> AptevaAppLifecycleResult {
        let body = try JSONEncoder().encode(AppStatusRequest(status: status))
        return try await request("apps/installs/\(installID)/status", method: "PUT", body: body)
    }

    public func uninstallApp(installID: Int64) async throws -> AptevaAppLifecycleResult {
        try await request("apps/installs/\(installID)", method: "DELETE")
    }

    public func nativeSurface(
        appName: String,
        descriptor: AptevaNativeSurfaceDescriptor,
        projectID: String
    ) async throws -> DeclaredNativeSurface {
        guard descriptor.supportsProjectApp,
              descriptor.entry.hasPrefix("/ui/"),
              descriptor.entry.hasSuffix(".json"),
              !descriptor.entry.split(separator: "/").contains("..") else {
            throw AptevaAPIError.invalidResponse
        }
        let surface: DeclaredNativeSurface = try await request(
            "apps/\(appName)\(descriptor.entry)?project_id=\(queryValue(projectID))"
        )
        guard surface.schema == descriptor.schema,
              surface.id == descriptor.id,
              surface.context.scope == "project" else {
            throw AptevaAPIError.invalidResponse
        }
        return surface
    }

    public func nativeDashboardWidgetSurface(
        appName: String,
        renderer: AptevaDashboardNativeRenderer,
        projectID: String
    ) async throws -> DeclaredNativeSurface {
        guard renderer.schema == "apteva-native-surface/v1",
              renderer.entry.hasPrefix("/ui/"),
              renderer.entry.hasSuffix(".json"),
              !renderer.entry.split(separator: "/").contains("..") else {
            throw AptevaAPIError.invalidResponse
        }
        let surface: DeclaredNativeSurface = try await request(
            "apps/\(appName)\(renderer.entry)?project_id=\(queryValue(projectID))"
        )
        guard surface.schema == renderer.schema,
              surface.context.scope == "project",
              surface.presentation == "widget" else {
            throw AptevaAPIError.invalidResponse
        }
        return surface
    }

    public func nativeAppJSON(
        appName: String,
        projectID: String,
        path: String,
        method: String,
        query: [String: String] = [:],
        body: [String: NativeJSONValue]? = nil
    ) async throws -> NativeJSONValue {
        guard let url = nativeAppURL(appName: appName, projectID: projectID, path: path, query: query) else {
            throw AptevaAPIError.invalidServerURL
        }
        let encodedBody = try body.map { try JSONEncoder().encode($0) }
        return try await request(url: url, requestPath: "apps/\(appName)\(path)", method: method, body: encodedBody)
    }

    public func nativeAppEventStream(
        appName: String,
        projectID: String,
        path: String,
        query: [String: String] = [:]
    ) -> AsyncThrowingStream<AptevaSSEEvent, Error> {
        guard let url = nativeAppURL(
            appName: appName,
            projectID: projectID,
            path: path,
            query: query
        ) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AptevaAPIError.invalidServerURL)
            }
        }
        return eventStream(url.absoluteString)
    }

    public func nativeAppData(
        appName: String,
        projectID: String,
        path: String
    ) async throws -> Data {
        guard let url = nativeAppURL(appName: appName, projectID: projectID, path: path) else {
            throw AptevaAPIError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        authorize(&request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AptevaAPIError.connection(connectionMessage(for: error))
        } catch {
            throw AptevaAPIError.connection(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AptevaAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw AptevaAPIError.server(
                status: http.statusCode,
                message: message?.isEmpty == false ? message! : "Server returned HTTP \(http.statusCode)."
            )
        }
        return data
    }

    /// Loads an API-provided asset reference. Same-origin assets receive the
    /// device bearer credential; third-party HTTPS assets never do.
    public func assetData(reference: String, maximumBytes: Int = 5_000_000) async throws -> Data {
        guard maximumBytes > 0,
              let url = resolvedAssetURL(reference) else {
            throw AptevaAPIError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if hasSameOrigin(url, baseURL) {
            authorize(&request)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AptevaAPIError.connection(connectionMessage(for: error))
        } catch {
            throw AptevaAPIError.connection(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AptevaAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AptevaAPIError.server(
                status: http.statusCode,
                message: "Asset request returned HTTP \(http.statusCode)."
            )
        }
        guard data.count <= maximumBytes else {
            throw AptevaAPIError.invalidResponse
        }
        return data
    }

    public func nativeAppDownload(
        appName: String,
        projectID: String,
        path: String,
        suggestedName: String
    ) async throws -> URL {
        guard let url = nativeAppURL(appName: appName, projectID: projectID, path: path) else {
            throw AptevaAPIError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        authorize(&request)
        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(for: request)
        } catch let error as URLError {
            throw AptevaAPIError.connection(connectionMessage(for: error))
        } catch {
            throw AptevaAPIError.connection(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AptevaAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AptevaAPIError.server(status: http.statusCode, message: "Server returned HTTP \(http.statusCode).")
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AptevaPreviews", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = URL(fileURLWithPath: suggestedName).lastPathComponent
        let destination = directory.appendingPathComponent(filename.isEmpty ? "Preview" : filename)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    public func nativeAppURL(
        appName: String,
        projectID: String,
        path: String,
        query: [String: String] = [:]
    ) -> URL? {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("://") else { return nil }
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !segments.contains("..") && !segments.contains(".") else { return nil }

        var url = baseURL
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("apps", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
        for segment in segments {
            url.appendPathComponent(String(segment))
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var items = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "project_id", value: projectID))
        components.queryItems = items.sorted { $0.name < $1.name }
        return components.url
    }

    private func request<Response: Decodable & Sendable>(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> Response {
        let apiBase = baseURL.appendingPathComponent("api", isDirectory: true)
        guard let url = URL(string: path, relativeTo: apiBase)?.absoluteURL else {
            throw AptevaAPIError.invalidServerURL
        }
        return try await request(url: url, requestPath: path, method: method, body: body, headers: headers)
    }

    private func request<Response: Decodable & Sendable>(
        url: URL,
        requestPath: String,
        method: String,
        body: Data?,
        headers: [String: String] = [:]
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AptevaAPIError.connection(connectionMessage(for: error))
        } catch {
            throw AptevaAPIError.connection(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AptevaAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            let rawMessage: String? = if contentType.contains("text/html") {
                nil
            } else {
                String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(800)
                    .description
            }
            let jsonMessage: String? = {
                guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                let primary = object["error"] as? String ?? object["message"] as? String
                let hint = object["hint"] as? String
                return [primary, hint].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            }()
            let message = jsonMessage?.isEmpty == false ? jsonMessage : rawMessage
            if http.statusCode == 401, requestPath == "auth/login" {
                throw AptevaAPIError.invalidCredentials
            }
            throw AptevaAPIError.server(
                status: http.statusCode,
                message: message?.isEmpty == false ? message! : "Server returned HTTP \(http.statusCode)."
            )
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw AptevaAPIError.invalidResponse
        }
    }

    private func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private func resolvedAssetURL(_ reference: String) -> URL? {
        let value = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let url: URL?
        if let absolute = URL(string: value), absolute.scheme != nil {
            url = absolute
        } else {
            let directoryBase = baseURL.appendingPathComponent("", isDirectory: true)
            url = URL(string: value, relativeTo: directoryBase)?.absoluteURL
        }
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.fragment == nil else {
            return nil
        }
        return url
    }

    private func hasSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }

    private func authorize(_ request: inout URLRequest) {
        guard let bearerToken, !bearerToken.isEmpty else { return }
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }

    private func connectionMessage(for error: URLError) -> String {
        switch error.code {
        case .cannotFindHost, .cannotConnectToHost:
            "Could not reach this Apteva server. Check its address and port."
        case .timedOut:
            "The Apteva server did not respond in time."
        case .notConnectedToInternet, .networkConnectionLost:
            "The local network connection is unavailable."
        case .serverCertificateUntrusted, .secureConnectionFailed:
            "The server’s TLS certificate could not be verified. Install a valid certificate for this hostname."
        default:
            error.localizedDescription
        }
    }
}

private struct LoginRequest: Encodable, Sendable {
    public let email: String
    public let password: String
}

private struct CreateAPIKeyRequest: Encodable, Sendable {
    public let name: String
    public let kind: String
    public let rateLimitPerMinute: Int

    public enum CodingKeys: String, CodingKey {
        case name, kind
        case rateLimitPerMinute = "rate_limit_per_minute"
    }
}

private struct AgentEventRequest: Encodable, Sendable {
    public let message: String
}

private struct AgentRenameRequest: Encodable, Sendable {
    public let name: String
}

private struct AgentConfigurationUpdateRequest: Encodable, Sendable {
    public let directive: String?
    public let mode: String
    public let providers: [AptevaAgentProviderConfiguration]?
}

private struct AgentMCPMutationRequest: Encodable, Sendable {
    public let action: String
    public let serverIDs: [Int64]

    public enum CodingKeys: String, CodingKey {
        case action
        case serverIDs = "mcp_server_ids"
    }
}

private struct AgentEventResponse: Decodable, Sendable {
    public let status: String
    public let threadID: String?

    public enum CodingKeys: String, CodingKey {
        case status
        case threadID = "thread_id"
    }
}

private struct CreateConversationRequest: Encodable, Sendable {
    public let projectID: String
    public let agentIDs: [Int64]
    public let title: String?
    public let leadAgentID: Int64?

    public enum CodingKeys: String, CodingKey {
        case title
        case projectID = "project_id"
        case agentIDs = "agent_ids"
        case leadAgentID = "lead_agent_id"
    }
}

private struct PostConversationMessageRequest: Encodable, Sendable {
    public let content: String
    public let attachments: [AptevaConversationAttachment]?
    public let clientMessageID: String

    public enum CodingKeys: String, CodingKey {
        case content, attachments
        case clientMessageID = "client_message_id"
    }
}

private struct ConversationSeenRequest: Encodable, Sendable {
    public let chatID: String
    public let lastSeenID: Int64

    public enum CodingKeys: String, CodingKey {
        case chatID = "chat_id"
        case lastSeenID = "last_seen_id"
    }
}

private struct ConversationSeenResponse: Decodable, Sendable {
    public let lastSeenID: Int64

    public enum CodingKeys: String, CodingKey {
        case lastSeenID = "last_seen_id"
    }
}

private struct ConversationPresenceRequest: Encodable, Sendable {
    public let chatID: String
    public let action: String

    public enum CodingKeys: String, CodingKey {
        case action
        case chatID = "chat_id"
    }
}

private struct StatusResponse: Decodable, Sendable {
    public let status: String
}

private struct MobilePushRegistrationRequest: Encodable, Sendable {
    public let installationID: String
    public let providerToken: String
    public let bundleID: String
    public let environment: String
    public let appVersion: String
    public let deviceName: String

    public enum CodingKeys: String, CodingKey {
        case installationID = "installation_id"
        case providerToken = "provider_token"
        case bundleID = "bundle_id"
        case environment
        case appVersion = "app_version"
        case deviceName = "device_name"
    }
}

private struct InboxActionRequest: Encodable, Sendable {
    public let messageID: Int64
    public let actionID: String

    public enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case actionID = "action_id"
    }
}

private struct InboxDismissRequest: Encodable, Sendable {
    public let messageID: Int64
    public enum CodingKeys: String, CodingKey { case messageID = "message_id" }
}

private struct InboxActionResponse: Decodable, Sendable {
    public let status: String
}

private struct InboxDismissResponse: Decodable, Sendable {
    public let dismissed: Bool
}

private struct AppPreflightRequest: Encodable, Sendable {
    public let manifestURL: String
    public let projectID: String

    public enum CodingKeys: String, CodingKey {
        case manifestURL = "manifest_url"
        case projectID = "project_id"
    }
}

private struct AppInstallRequest: Encodable, Sendable {
    public let manifestURL: String
    public let projectID: String
    public let config: [String: String]
    public let upgradePolicy: String
    public let bindings: [String: AptevaAppBinding]

    public enum CodingKeys: String, CodingKey {
        case manifestURL = "manifest_url"
        case projectID = "project_id"
        case config
        case upgradePolicy = "upgrade_policy"
        case bindings
    }
}

private struct AppUpgradeRequest: Encodable, Sendable {
    public let approveNewPermissions: Bool
    public enum CodingKeys: String, CodingKey { case approveNewPermissions = "approve_new_permissions" }
}

private struct AppStatusRequest: Encodable, Sendable {
    public let status: String
}

private extension AptevaInboxItem {
    init(_ row: AptevaApprovalMessage) {
        let component = row.message.components?.first { $0.app == "channel-chat" && $0.name == "approval-card" }
        let rawActions = component?.props?["actions"]?.arrayValue ?? []
        let parsedActions = rawActions.compactMap { value -> AptevaInboxAction? in
            guard let object = value.objectValue,
                  let id = object["id"]?.stringValue,
                  let label = object["label"]?.stringValue else { return nil }
            return AptevaInboxAction(id: id, label: label, style: object["style"]?.stringValue ?? "")
        }
        self.init(
            kind: .approval,
            messageID: row.message.id,
            instanceID: row.instanceID,
            instanceName: row.instanceName,
            title: row.title.isEmpty ? row.message.content : row.title,
            body: row.body,
            meta: row.status,
            createdAt: parseAptevaDate(row.message.createdAt) ?? .distantPast,
            actions: parsedActions.isEmpty
                ? [AptevaInboxAction(id: "approve", label: "Approve", style: "primary"), AptevaInboxAction(id: "deny", label: "Deny", style: "danger")]
                : parsedActions
        )
    }

    init(_ row: AptevaReportMessage) {
        self.init(
            kind: .report,
            messageID: row.message.id,
            instanceID: row.instanceID,
            instanceName: row.instanceName,
            title: row.title.isEmpty ? row.message.content : row.title,
            body: row.summary,
            meta: row.period ?? "Report",
            createdAt: parseAptevaDate(row.message.createdAt) ?? .distantPast,
            actions: []
        )
    }

    init(_ row: AptevaAlertMessage) {
        self.init(
            kind: .alert,
            messageID: row.message.id,
            instanceID: row.instanceID,
            instanceName: row.instanceName,
            title: row.title.isEmpty ? row.message.content : row.title,
            body: row.body,
            meta: row.severity,
            createdAt: parseAptevaDate(row.message.createdAt) ?? .distantPast,
            actions: []
        )
    }
}
