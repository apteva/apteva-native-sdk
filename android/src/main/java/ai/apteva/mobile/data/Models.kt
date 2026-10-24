package ai.apteva.mobile.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

@Serializable
data class AuthStatus(
    @SerialName("reg_mode") val registrationMode: String = "closed",
    @SerialName("needs_setup") val needsSetup: Boolean = false,
)

@Serializable
data class AptevaUser(
    @SerialName("user_id") val userId: Long,
    val email: String,
    val role: String? = null,
)

@Serializable
data class CreatedApiKey(
    val id: Long,
    val name: String,
    val key: String,
    val prefix: String = "",
    val kind: String = "private",
)

@Serializable
data class Project(
    val id: String,
    val name: String,
    val description: String = "",
    val color: String = "",
)

@Serializable
data class Agent(
    val id: Long,
    val name: String,
    val status: String,
    val mode: String,
    val directive: String? = null,
    val kind: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class AgentProviderConfiguration(
    val name: String,
    @SerialName("default") val isDefault: Boolean = false,
    val models: Map<String, String>? = null,
)

@Serializable
data class AgentMcpServerConfiguration(
    val name: String,
    val transport: String? = null,
    val url: String? = null,
    val command: String? = null,
    val args: List<String>? = null,
    val connected: Boolean? = null,
)

@Serializable
data class AgentConfiguration(
    val directive: String = "",
    val mode: String,
    val providers: List<AgentProviderConfiguration> = emptyList(),
    @SerialName("mcp_servers") val mcpServers: List<AgentMcpServerConfiguration> = emptyList(),
)

@Serializable
data class RuntimeConnection(
    val id: Long,
    val name: String,
    @SerialName("app_slug") val appSlug: String = "",
    @SerialName("app_name") val appName: String = "",
    @SerialName("provider_key") val providerKey: String,
    val role: String,
    @SerialName("project_id") val projectId: String = "",
    val scope: String = "global",
    @SerialName("is_primary") val isPrimary: Boolean = false,
)

@Serializable
data class Connection(
    val id: Long,
    @SerialName("app_slug") val appSlug: String = "",
    @SerialName("app_name") val appName: String = appSlug,
    val name: String = appName,
    val status: String = "",
    val source: String = "",
    @SerialName("project_id") val projectId: String? = null,
    val logo: String = "",
    @SerialName("tool_count") val toolCount: Int = 0,
)

@Serializable
data class McpProxyConfiguration(
    val name: String,
    val transport: String = "",
)

@Serializable
data class McpServer(
    val id: Long,
    val name: String = "",
    val description: String = "",
    val status: String,
    val source: String = "",
    @SerialName("tool_count") val toolCount: Int = 0,
    @SerialName("owner_app_install_id") val ownerAppInstallId: Long? = null,
    @SerialName("connection_id") val connectionId: Long? = null,
    @SerialName("created_via") val createdVia: String? = null,
    @SerialName("proxy_config") val proxyConfiguration: McpProxyConfiguration? = null,
) {
    val attachmentName: String get() = proxyConfiguration?.name ?: name
    val displayName: String get() = description.ifBlank { name }
}

@Serializable
data class AgentStats(
    @SerialName("instance_id") val instanceId: Long,
    val name: String = "",
    val status: String = "",
    @SerialName("llm_calls") val llmCalls: Int = 0,
    @SerialName("tokens_in") val tokensIn: Int = 0,
    @SerialName("tokens_out") val tokensOut: Int = 0,
    val cost: Double = 0.0,
    val errors: Int = 0,
    @SerialName("tool_calls") val toolCalls: Int = 0,
)

@Serializable
data class TelemetryEvent(
    val id: String,
    @SerialName("instance_id") val instanceId: Long,
    @SerialName("thread_id") val threadId: String = "",
    val type: String,
    val time: String,
    val data: JsonObject = JsonObject(emptyMap()),
)

@Serializable
data class AgentChatMessage(
    val id: String,
    val role: String,
    val text: String = "",
    val time: String,
    @SerialName("tool_name") val toolName: String? = null,
    @SerialName("tool_done") val toolDone: Boolean? = null,
    @SerialName("tool_duration_ms") val toolDurationMs: Long? = null,
    @SerialName("tool_success") val toolSuccess: Boolean? = null,
)

@Serializable
data class ChannelComponent(
    val app: String,
    val name: String,
    val props: JsonObject? = null,
)

@Serializable
data class ChannelMessage(
    val id: Long,
    val content: String = "",
    @SerialName("created_at") val createdAt: String,
    val components: List<ChannelComponent>? = null,
)

@Serializable
data class CurrentStatus(
    val message: ChannelMessage,
    @SerialName("instance_id") val instanceId: Long,
    @SerialName("instance_name") val instanceName: String,
    @SerialName("project_id") val projectId: String,
    @SerialName("updated_at") val updatedAt: String? = null,
    val title: String = "",
    val detail: String? = null,
    val state: String = "unknown",
    val progress: Double? = null,
    val next: String? = null,
    @SerialName("next_at") val nextAt: String? = null,
    val stale: Boolean = false,
)

@Serializable
data class Conversation(
    val id: String,
    @SerialName("instance_id") val instanceId: Long,
    @SerialName("agent_ids") val agentIds: List<Long> = emptyList(),
    @SerialName("project_id") val projectId: String,
    val kind: String = "direct",
    val title: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("archived_at") val archivedAt: String? = null,
    @SerialName("thread_id") val threadId: String? = null,
)

@Serializable
data class ConversationAttachment(
    val id: String? = null,
    val type: String,
    @SerialName("data_url") val dataUrl: String? = null,
    val name: String? = null,
    @SerialName("mime_type") val mimeType: String? = null,
    val size: Int? = null,
    val ephemeral: Boolean? = null,
)

@Serializable
data class ConversationMessage(
    val id: Long,
    @SerialName("chat_id") val chatId: String,
    val role: String,
    val content: String = "",
    @SerialName("user_id") val userId: Long? = null,
    @SerialName("agent_id") val agentId: Long? = null,
    @SerialName("thread_id") val threadId: String? = null,
    val status: String = "sent",
    @SerialName("created_at") val createdAt: String,
    val components: List<ChannelComponent>? = null,
    val attachments: List<ConversationAttachment>? = null,
    val metadata: JsonObject? = null,
    @SerialName("client_message_id") val clientMessageId: String? = null,
) {
    val phase: String
        get() = (metadata?.get("phase") as? kotlinx.serialization.json.JsonPrimitive)?.content ?: "final"
}

@Serializable
data class UnreadConversation(
    @SerialName("chat_id") val chatId: String,
    @SerialName("instance_id") val instanceId: Long,
    @SerialName("instance_name") val instanceName: String,
    val title: String,
    @SerialName("latest_id") val latestId: Long,
    @SerialName("latest_role") val latestRole: String,
    @SerialName("latest_preview") val latestPreview: String = "",
    @SerialName("latest_at") val latestAt: String,
    @SerialName("last_seen_id") val lastSeenId: Long = 0,
)

@Serializable
data class ChatStreamFrame(
    @SerialName("chat_id") val chatId: String,
    @SerialName("call_id") val callId: String,
    val text: String = "",
    val phase: String? = null,
    val done: Boolean = false,
)

data class SseEvent(val id: String?, val name: String?, val data: String)

enum class RealtimeConnectionState { Disconnected, Connecting, Reconnecting, Connected }

@Serializable
data class ApprovalMessage(
    val message: ChannelMessage,
    @SerialName("instance_id") val instanceId: Long,
    @SerialName("instance_name") val instanceName: String,
    @SerialName("project_id") val projectId: String,
    val title: String = "",
    val body: String = "",
    val status: String = "pending",
)

@Serializable
data class ReportMessage(
    val message: ChannelMessage,
    @SerialName("instance_id") val instanceId: Long,
    @SerialName("instance_name") val instanceName: String,
    @SerialName("project_id") val projectId: String,
    val title: String = "",
    val summary: String = "",
    val period: String? = null,
)

@Serializable
data class AlertMessage(
    val message: ChannelMessage,
    @SerialName("instance_id") val instanceId: Long,
    @SerialName("instance_name") val instanceName: String,
    @SerialName("project_id") val projectId: String,
    val title: String = "",
    val body: String = "",
    val severity: String = "alert",
)

enum class InboxKind { Approval, Report, Alert }

data class InboxAction(val id: String, val label: String, val style: String = "")

data class InboxItem(
    val kind: InboxKind,
    val messageId: Long,
    val instanceName: String,
    val title: String,
    val body: String,
    val meta: String,
    val createdAt: String,
    val actions: List<InboxAction> = emptyList(),
)

@Serializable
data class MobilePushConfig(
    val enabled: Boolean = false,
    @SerialName("supports_background_refresh") val supportsBackgroundRefresh: Boolean = false,
    @SerialName("supports_app_notifications") val supportsAppNotifications: Boolean = false,
    @SerialName("instance_ref") val instanceRef: String? = null,
)

@Serializable
data class NotificationChannels(
    @SerialName("in_app") val inApp: Boolean,
    val tab: Boolean,
    val desktop: Boolean,
    val mobile: Boolean,
)

@Serializable
data class UserNotification(
    val id: Long,
    @SerialName("install_id") val installId: Long,
    @SerialName("project_id") val projectId: String,
    val type: String,
    val app: String,
    val title: String,
    val body: String,
    val url: String,
    val group: String,
    val read: Boolean,
    val channels: NotificationChannels,
    @SerialName("app_name") val appName: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class NotificationSnapshot(
    val items: List<UserNotification>,
    @SerialName("unread_count") val unreadCount: Int,
    @SerialName("tab_count") val tabCount: Int,
    @SerialName("next_before") val nextBefore: Long,
)

@Serializable
data class MobilePushSubscription(
    val id: String,
    @SerialName("installation_id") val installationId: String,
    val platform: String = "ios",
    @SerialName("relay_device_id") val relayDeviceId: String = "",
    @SerialName("grant_expires_at") val grantExpiresAt: String = "",
    @SerialName("bundle_id") val bundleId: String,
    val environment: String,
    @SerialName("app_version") val appVersion: String = "",
    @SerialName("device_name") val deviceName: String = "",
    val status: String = "active",
    @SerialName("last_badge") val lastBadge: Int = 0,
    @SerialName("last_error") val lastError: String = "",
    @SerialName("last_success_at") val lastSuccessAt: String = "",
)

@Serializable
data class MobilePushSubscriptionsResponse(
    val subscriptions: List<MobilePushSubscription> = emptyList(),
)

@Serializable
data class MobilePushRegistrationResponse(
    val subscription: MobilePushSubscription,
)

@Serializable
data class NativeSurfaceDescriptor(
    val id: String,
    val label: String,
    val icon: String = "",
    val schema: String,
    val entry: String,
    val slots: List<String> = emptyList(),
) {
    val supportsProjectApp: Boolean
        get() = schema == "apteva-native-surface/v1" && "mobile.project_app" in slots
}

@Serializable
data class InstalledApp(
    @SerialName("install_id") val installId: Long,
    @SerialName("app_id") val appId: Long,
    val name: String,
    @SerialName("display_name") val displayName: String = name,
    val version: String,
    @SerialName("available_version") val availableVersion: String? = null,
    val description: String = "",
    val icon: String = "",
    @SerialName("project_id") val projectId: String,
    val status: String,
    @SerialName("status_message") val statusMessage: String? = null,
    @SerialName("error_message") val errorMessage: String? = null,
    val source: String,
    @SerialName("upgrade_policy") val upgradePolicy: String,
    val deprecated: Boolean = false,
    @SerialName("ui_surfaces") val uiSurfaces: List<NativeSurfaceDescriptor> = emptyList(),
) {
    val updateAvailable: Boolean
        get() = !deprecated && !availableVersion.isNullOrBlank() && availableVersion != version
    val lifecycleManaged: Boolean get() = source != "builtin" && source != "integration"
}

@Serializable
data class MarketplaceResponse(
    @SerialName("registry_url") val registryUrl: String = "",
    val apps: List<MarketplaceApp> = emptyList(),
    val total: Int? = null,
    val categories: Map<String, Int>? = null,
)

@Serializable
data class MarketplaceApp(
    val name: String,
    @SerialName("display_name") val displayName: String = name,
    val version: String,
    val description: String = "",
    val author: String = "",
    @SerialName("manifest_url") val manifestUrl: String = "",
    val icon: String = "",
    val tags: List<String> = emptyList(),
    val official: Boolean,
    val category: String = "",
    val installed: Boolean,
    val builtin: Boolean,
    val deprecated: Boolean = false,
)

@Serializable
data class LifecycleResult(val status: String, val version: String? = null)

@Serializable
data class InstallResult(
    @SerialName("install_id") val installId: Long = 0,
    val status: String,
    val error: String? = null,
)

@Serializable
data class NativeSurface(
    val schema: String,
    val id: String,
    val version: String = "",
    val title: String,
    val description: String? = null,
    val icon: String = "",
    val context: SurfaceContext,
    val state: Map<String, SurfaceState> = emptyMap(),
    @SerialName("data_sources") val dataSources: Map<String, SurfaceDataSource> = emptyMap(),
    val sections: List<SurfaceSection> = emptyList(),
    val destinations: Map<String, SurfaceDestination> = emptyMap(),
    val actions: Map<String, SurfaceAction> = emptyMap(),
    val presentation: String? = null,
    val blocks: List<SurfaceBlock> = emptyList(),
    val navigation: SurfaceNavigation? = null,
)

@Serializable data class SurfaceNavigation(val surface: String)

@Serializable
data class SurfaceBlock(
    val id: String,
    val type: String,
    val title: String? = null,
    val label: String? = null,
    val source: String? = null,
    val value: String? = null,
    val text: String? = null,
    val format: String? = null,
    val icon: String? = null,
    val items: String? = null,
    val item: SurfaceItem? = null,
    val metrics: List<SurfaceBlockMetric> = emptyList(),
    val limit: Int? = null,
    val action: String? = null,
    @SerialName("visible_if") val visibleIf: String? = null,
)

@Serializable data class SurfaceBlockMetric(val label: String, val value: String, val format: String? = null, val icon: String? = null)

@Serializable
data class SurfaceAction(
    val type: String,
    val label: String,
    val icon: String? = null,
    val request: SurfaceRequest,
)

@Serializable
data class DashboardWidgetSurface(
    val surface: String,
    @SerialName("project_id") val projectId: String,
    val revision: Long,
    val layout: List<DashboardWidgetInstance>,
    val definitions: List<DashboardWidgetDefinition>,
)

@Serializable
data class DashboardWidgetInstance(
    val id: String,
    val component: String,
    val size: String = "half",
    val settings: Map<String, JsonElement> = emptyMap(),
)

@Serializable
data class DashboardWidgetDefinition(
    val component: String,
    val kind: String,
    val app: String? = null,
    @SerialName("install_id") val installId: Long? = null,
    val label: String,
    val description: String? = null,
    val icon: String? = null,
    @SerialName("supported_sizes") val supportedSizes: List<String> = listOf("half"),
    @SerialName("default_size") val defaultSize: String = "half",
    @SerialName("default_settings") val defaultSettings: Map<String, JsonElement> = emptyMap(),
    @SerialName("settings_schema") val settingsSchema: Map<String, JsonElement> = emptyMap(),
    @SerialName("refresh_topics") val refreshTopics: List<String> = emptyList(),
    val suggested: Boolean = false,
    val native: DashboardNativeRenderer? = null,
    @SerialName("project_surfaces") val projectSurfaces: List<NativeSurfaceDescriptor> = emptyList(),
)

@Serializable data class DashboardNativeRenderer(val schema: String, val entry: String)
@Serializable data class DashboardLayoutPatchRequest(val value: List<DashboardWidgetInstance>)
@Serializable data class DashboardLayoutPatchResponse(val value: List<DashboardWidgetInstance>, val revision: Long)

@Serializable
data class AppEventEnvelope(
    val topic: String,
    val app: String,
    @SerialName("project_id") val projectId: String,
    @SerialName("install_id") val installId: Long? = null,
    @SerialName("seq") val sequence: Long? = null,
    val data: JsonElement? = null,
)

@Serializable data class SurfaceContext(val scope: String)

@Serializable
data class SurfaceState(
    val type: String,
    @SerialName("default") val defaultValue: JsonElement? = null,
    val persistence: String? = null,
)

@Serializable
data class SurfaceDataSource(
    val request: SurfaceRequest,
    val response: SurfaceResponse,
)

@Serializable
data class SurfaceRequest(
    val method: String = "GET",
    val path: String,
    val query: Map<String, JsonElement> = emptyMap(),
    val body: Map<String, JsonElement> = emptyMap(),
)

@Serializable
data class SurfaceResponse(
    val items: String? = null,
    val item: String? = null,
    val id: String? = null,
    val result: String? = null,
)

@Serializable
data class SurfaceSection(
    val id: String,
    val kind: String,
    val title: String? = null,
    val description: String? = null,
    val source: String? = null,
    val search: SurfaceSearch? = null,
    val item: SurfaceItem? = null,
    val fields: List<SurfaceField> = emptyList(),
    val preview: SurfacePreview? = null,
)

@Serializable
data class SurfaceSearch(
    val state: String,
    val placeholder: String = "Search",
    @SerialName("query_key") val queryKey: String? = null,
)

@Serializable
data class SurfaceItem(
    val id: String,
    val title: String,
    val subtitle: List<SurfaceValue> = emptyList(),
    val badge: SurfaceValue? = null,
    val destination: String? = null,
)

@Serializable
data class SurfaceValue(
    val value: String,
    val label: String? = null,
    val format: String? = null,
    val fallback: String? = null,
)

@Serializable
data class SurfaceDestination(
    val type: String,
    val title: String? = null,
    val source: String? = null,
    val sections: List<SurfaceSection> = emptyList(),
)

@Serializable
data class SurfaceField(
    val id: String? = null,
    val label: String,
    val value: String,
    val format: String? = null,
    val hidden: Boolean? = null,
)

@Serializable
data class SurfacePreview(
    val path: String,
    val name: String? = null,
    @SerialName("content_type") val contentType: String? = null,
)
