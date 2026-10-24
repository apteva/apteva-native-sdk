package ai.apteva.mobile.data

import android.content.Context
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

class ApiException(message: String, val status: Int? = null) : IOException(message)

class PersistentCookieJar(context: Context) : CookieJar {
    private val preferences = context.getSharedPreferences("apteva.cookies", Context.MODE_PRIVATE)
    private val lock = Any()

    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) = synchronized(lock) {
        val current = loadAll(url).associateBy { "${it.name}|${it.domain}|${it.path}" }.toMutableMap()
        cookies.forEach { cookie ->
            val key = "${cookie.name}|${cookie.domain}|${cookie.path}"
            if (cookie.expiresAt < System.currentTimeMillis()) current.remove(key) else current[key] = cookie
        }
        preferences.edit().putStringSet("cookies", current.values.map(Cookie::toString).toSet()).apply()
    }

    override fun loadForRequest(url: HttpUrl): List<Cookie> = synchronized(lock) {
        loadAll(url).filter { it.matches(url) && it.expiresAt >= System.currentTimeMillis() }
    }

    fun clear() = preferences.edit().clear().apply()

    private fun loadAll(url: HttpUrl): List<Cookie> = preferences.getStringSet("cookies", emptySet())
        .orEmpty().mapNotNull { Cookie.parse(url, it) }
}

class ApiClient(
    val baseUrl: String,
    private val cookieJar: PersistentCookieJar,
    private val bearerToken: String? = null,
) {
    companion object {
        val json = Json {
            ignoreUnknownKeys = true
            explicitNulls = false
            encodeDefaults = false
        }
        private val jsonType = "application/json; charset=utf-8".toMediaType()

        fun normalizeServer(input: String): String {
            var value = input.trim()
            if (value.isBlank()) throw ApiException("Enter a valid server address.")
            if (!value.contains("://")) value = "https://$value"
            val parsed = value.toHttpUrlOrNull() ?: throw ApiException("Enter a valid server address.")
            if (parsed.scheme != "https") throw ApiException("The server address must use HTTPS.")
            if (parsed.username.isNotEmpty() || parsed.password.isNotEmpty() || parsed.query != null || parsed.fragment != null) {
                throw ApiException("Enter a server address without credentials, query parameters, or fragments.")
            }
            return parsed.toString().trimEnd('/')
        }
    }

    private val client = OkHttpClient.Builder()
        .cookieJar(cookieJar)
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    suspend inline fun <reified T> get(path: String): T = decode(execute("GET", path))
    suspend inline fun <reified T> post(path: String, body: JsonElement = JsonObject(emptyMap())): T =
        decode(execute("POST", path, body.toString()))
    suspend inline fun <reified T> put(path: String, body: JsonElement): T = decode(execute("PUT", path, body.toString()))
    suspend inline fun <reified T> delete(path: String): T = decode(execute("DELETE", path))

    suspend fun authStatus(): AuthStatus = get("auth/status")
    suspend fun login(email: String, password: String): AptevaUser = post(
        "auth/login",
        JsonObject(mapOf("email" to JsonPrimitive(email), "password" to JsonPrimitive(password))),
    )
    suspend fun currentUser(): AptevaUser = get("auth/me")
    suspend fun projects(): List<Project> = get("projects")
    suspend fun logout() { execute("POST", "auth/logout", "{}") }
    suspend fun createDeviceApiKey(name: String): CreatedApiKey = post(
        "auth/keys",
        JsonObject(mapOf(
            "name" to JsonPrimitive(name),
            "kind" to JsonPrimitive("private"),
            "rate_limit_per_minute" to JsonPrimitive(600),
        )),
    )
    suspend fun deleteApiKey(id: Long) { execute("DELETE", "auth/keys/$id") }

    suspend fun agents(projectId: String): List<Agent> = get("agents?project_id=${encode(projectId)}")
    suspend fun agent(id: Long): Agent = get("agents/$id")
    suspend fun renameAgent(id: Long, name: String): Agent = put(
        "agents/$id",
        JsonObject(mapOf("name" to JsonPrimitive(name))),
    )
    suspend fun agentConfiguration(id: Long): AgentConfiguration = get("agents/$id/config")
    suspend fun updateAgentConfiguration(
        id: Long,
        directive: String?,
        mode: String,
        providers: List<AgentProviderConfiguration>?,
    ) {
        execute("PUT", "agents/$id/config", buildJsonObject {
            directive?.let { put("directive", JsonPrimitive(it)) }
            put("mode", JsonPrimitive(mode))
            providers?.let {
                put("providers", json.encodeToJsonElement(
                    kotlinx.serialization.builtins.ListSerializer(AgentProviderConfiguration.serializer()),
                    it,
                ))
            }
        }.toString())
    }
    suspend fun runtimeConnections(projectId: String): List<RuntimeConnection> =
        get("connections/runtime?project_id=${encode(projectId)}")
    suspend fun connections(projectId: String): List<Connection> =
        get("connections?project_id=${encode(projectId)}")
    suspend fun mcpServers(projectId: String): List<McpServer> =
        get("mcp-servers?project_id=${encode(projectId)}")
    suspend fun mutateAgentMcpServers(id: Long, serverIds: List<Long>, action: String) {
        execute("POST", "agents/$id/mcp-servers", buildJsonObject {
            put("action", JsonPrimitive(action))
            put("mcp_server_ids", JsonArray(serverIds.map(::JsonPrimitive)))
        }.toString())
    }
    suspend fun startAgent(id: Long): Agent = post("agents/$id/start")
    suspend fun stopAgent(id: Long): Agent = post("agents/$id/stop")
    suspend fun sendAgentEvent(id: Long, message: String) {
        execute("POST", "agents/$id/event", JsonObject(mapOf("message" to JsonPrimitive(message))).toString())
    }
    suspend fun agentHistory(id: Long, limit: Int = 60): List<AgentChatMessage> =
        get("agents/$id/chat-history?limit=${limit.coerceIn(1, 200)}")
    suspend fun telemetry(id: Long, limit: Int = 60): List<TelemetryEvent> =
        get("telemetry?agent_id=$id&limit=${limit.coerceIn(1, 1000)}")
    suspend fun telemetry(
        id: Long,
        type: String,
        limit: Int,
        since: String,
        threadId: String,
    ): List<TelemetryEvent> = get(
        "telemetry?agent_id=$id&type=${encode(type)}&limit=${limit.coerceIn(1, 1000)}&since=${encode(since)}&thread_id=${encode(threadId)}",
    )
    suspend fun projectStats(projectId: String): List<AgentStats> =
        get("telemetry/project-stats?project_id=${encode(projectId)}&period=24h")
    suspend fun currentStatuses(projectId: String): List<CurrentStatus> =
        get("apps/channel-chat/current-statuses?project_id=${encode(projectId)}")

    suspend fun conversations(projectId: String): List<Conversation> =
        get("apps/channel-chat/conversations?project_id=${encode(projectId)}")
    suspend fun conversationsForAgent(agentId: Long): List<Conversation> =
        get<List<Conversation>>("apps/channel-chat/chats?instance_id=$agentId")
            .filterNot { it.id.startsWith("default-") }
    suspend fun createConversation(
        projectId: String,
        agentIds: List<Long>,
        title: String? = null,
        leadAgentId: Long? = null,
    ): Conversation = post(
        "apps/channel-chat/conversations",
        buildJsonObject {
            put("project_id", JsonPrimitive(projectId))
            put("agent_ids", JsonArray(agentIds.map(::JsonPrimitive)))
            title?.let { put("title", JsonPrimitive(it)) }
            leadAgentId?.let { put("lead_agent_id", JsonPrimitive(it)) }
        },
    )
    suspend fun conversationMessages(chatId: String, since: Long = 0, limit: Int = 500): List<ConversationMessage> =
        get("apps/channel-chat/messages?chat_id=${encode(chatId)}&since=$since&limit=${limit.coerceIn(1, 1000)}")
    suspend fun sendConversationMessage(
        chatId: String,
        content: String,
        attachments: List<ConversationAttachment> = emptyList(),
        clientMessageId: String,
    ): ConversationMessage = post(
        "apps/channel-chat/messages?chat_id=${encode(chatId)}",
        buildJsonObject {
            put("content", JsonPrimitive(content))
            put("client_message_id", JsonPrimitive(clientMessageId))
            if (attachments.isNotEmpty()) {
                put("attachments", json.encodeToJsonElement(kotlinx.serialization.builtins.ListSerializer(ConversationAttachment.serializer()), attachments))
            }
        },
    )
    suspend fun unreadConversations(): List<UnreadConversation> = get("apps/channel-chat/unread-summary")

    /**
     * The unread endpoint is user-wide. Project surfaces must scope those rows
     * against the server's real project conversation collection.
     */
    suspend fun unreadConversations(projectId: String): List<UnreadConversation> = coroutineScope {
        val unreadRequest = async { unreadConversations() }
        val conversationRequest = async { conversations(projectId) }
        val projectConversationIds = conversationRequest.await().mapTo(mutableSetOf()) { it.id }
        unreadRequest.await().filter { it.chatId in projectConversationIds }
    }
    suspend fun markConversationSeen(chatId: String, lastSeenId: Long) {
        execute("POST", "apps/channel-chat/seen", JsonObject(mapOf(
            "chat_id" to JsonPrimitive(chatId),
            "last_seen_id" to JsonPrimitive(lastSeenId),
        )).toString())
    }
    suspend fun updateConversationPresence(chatId: String, connected: Boolean) {
        execute("POST", "apps/channel-chat/presence", JsonObject(mapOf(
            "chat_id" to JsonPrimitive(chatId),
            "action" to JsonPrimitive(if (connected) "connected" else "disconnected"),
        )).toString())
    }

    suspend fun inbox(projectId: String, limit: Int = 12): List<InboxItem> {
        val project = encode(projectId)
        val approvals: List<ApprovalMessage> = get("apps/channel-chat/approval-messages?project_id=$project&status=pending&limit=$limit")
        val reports: List<ReportMessage> = get("apps/channel-chat/report-messages?project_id=$project&limit=$limit")
        val alerts: List<AlertMessage> = get("apps/channel-chat/alert-messages?project_id=$project&limit=$limit")
        return buildList {
            approvals.forEach { row ->
                val rawActions = row.message.components.orEmpty()
                    .firstOrNull { it.app == "channel-chat" && it.name == "approval-card" }
                    ?.props?.get("actions") as? JsonArray
                val actions = rawActions.orEmpty().mapNotNull { raw ->
                    val obj = raw as? JsonObject ?: return@mapNotNull null
                    val id = (obj["id"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                    val label = (obj["label"] as? JsonPrimitive)?.contentOrNull ?: return@mapNotNull null
                    InboxAction(id, label, (obj["style"] as? JsonPrimitive)?.contentOrNull.orEmpty())
                }.ifEmpty { listOf(InboxAction("approve", "Approve", "primary"), InboxAction("deny", "Deny", "danger")) }
                add(InboxItem(InboxKind.Approval, row.message.id, row.instanceName, row.title.ifBlank { row.message.content }, row.body, row.status, row.message.createdAt, actions))
            }
            reports.forEach { row -> add(InboxItem(InboxKind.Report, row.message.id, row.instanceName, row.title.ifBlank { row.message.content }, row.summary, row.period ?: "Report", row.message.createdAt)) }
            alerts.forEach { row -> add(InboxItem(InboxKind.Alert, row.message.id, row.instanceName, row.title.ifBlank { row.message.content }, row.body, row.severity, row.message.createdAt)) }
        }.sortedByDescending { it.messageId }.take(limit)
    }

    suspend fun inboxAction(messageId: Long, actionId: String) {
        execute("POST", "apps/channel-chat/message-action", JsonObject(mapOf("message_id" to JsonPrimitive(messageId), "action_id" to JsonPrimitive(actionId))).toString())
    }
    suspend fun dismissInbox(messageId: Long) {
        execute("POST", "apps/channel-chat/message-dismiss", JsonObject(mapOf("message_id" to JsonPrimitive(messageId))).toString())
    }

    suspend fun mobilePushConfig(): MobilePushConfig = get("mobile/push/config")
    suspend fun userNotifications(): NotificationSnapshot = get("notifications")
    suspend fun userNotification(id: Long): UserNotification {
        require(id > 0)
        return get("notifications/$id")
    }
    suspend fun markUserNotificationRead(id: Long) {
        require(id > 0)
        execute("PATCH", "notifications/$id", """{"read":true}""")
    }
    suspend fun mobilePushSubscriptions(): List<MobilePushSubscription> =
        get<MobilePushSubscriptionsResponse>("mobile/push/subscriptions").subscriptions
    suspend fun registerMobilePush(
        installationId: String,
        providerToken: String,
        bundleId: String,
        appVersion: String,
        deviceName: String,
    ): MobilePushSubscription = post<MobilePushRegistrationResponse>(
        "mobile/push/subscriptions",
        JsonObject(mapOf(
            "installation_id" to JsonPrimitive(installationId),
            "provider_token" to JsonPrimitive(providerToken),
            "platform" to JsonPrimitive("android"),
            "bundle_id" to JsonPrimitive(bundleId),
            "environment" to JsonPrimitive("production"),
            "app_version" to JsonPrimitive(appVersion),
            "device_name" to JsonPrimitive(deviceName),
        )),
    ).subscription
    suspend fun deleteMobilePushSubscription(id: String) {
        delete<JsonObject>("mobile/push/subscriptions/${encode(id)}")
    }
    suspend fun testMobilePushSubscription(id: String) {
        post<JsonObject>("mobile/push/subscriptions/${encode(id)}/test")
    }

    suspend fun installedApps(projectId: String): List<InstalledApp> = get("apps?project_id=${encode(projectId)}")
    suspend fun dashboardWidgetSurface(projectId: String): DashboardWidgetSurface =
        get("ui/surfaces/dashboard.home?project_id=${encode(projectId)}")
    suspend fun updateDashboardWidgetLayout(
        projectId: String,
        layout: List<DashboardWidgetInstance>,
        revision: Long,
    ): DashboardLayoutPatchResponse = decode(execute(
        "PATCH",
        "ui-layout/projects/${encode(projectId)}/surfaces/dashboard.home",
        json.encodeToString(DashboardLayoutPatchRequest(layout)),
        mapOf("If-Match" to "\"$revision\""),
    ))
    suspend fun marketplace(projectId: String): MarketplaceResponse = get("apps/marketplace?project_id=${encode(projectId)}&page_size=100")

    /**
     * Loads an API-provided asset reference. Same-origin assets receive the
     * device bearer credential; third-party HTTPS assets never do.
     */
    suspend fun assetData(reference: String, maximumBytes: Int = 5_000_000): ByteArray = withContext(Dispatchers.IO) {
        if (maximumBytes <= 0) throw ApiException("Invalid asset size limit.")
        val value = reference.trim()
        if (value.isEmpty()) throw ApiException("Invalid asset URL.")
        val server = baseUrl.toHttpUrlOrNull() ?: throw ApiException("Invalid server URL.")
        val url = if (value.contains("://")) value.toHttpUrlOrNull() else server.resolve(value)
        if (url == null || url.scheme != "https" || url.host.isBlank() ||
            url.username.isNotEmpty() || url.password.isNotEmpty() || url.fragment != null
        ) throw ApiException("Invalid asset URL.")

        val builder = Request.Builder().url(url).header("Accept", "image/*")
        val sameOrigin = url.scheme == server.scheme && url.host == server.host && url.port == server.port
        if (sameOrigin) bearerToken?.takeIf(String::isNotBlank)?.let {
            builder.header("Authorization", "Bearer $it")
        }
        val response = try { client.newCall(builder.build()).execute() }
        catch (error: IOException) { throw ApiException("Could not load this asset: ${error.message}") }
        response.use {
            if (!it.isSuccessful) throw ApiException("Asset request returned HTTP ${it.code}.", it.code)
            val body = it.body ?: throw ApiException("Asset request returned no body.")
            if (body.contentLength() > maximumBytes) throw ApiException("Asset exceeds the size limit.")
            body.bytes().also { bytes ->
                if (bytes.size > maximumBytes) throw ApiException("Asset exceeds the size limit.")
            }
        }
    }
    suspend fun updateApp(installId: Long): LifecycleResult = post("apps/installs/$installId/upgrade", JsonObject(mapOf("approve_new_permissions" to JsonPrimitive(false))))
    suspend fun setAppStatus(installId: Long, status: String): LifecycleResult = put("apps/installs/$installId/status", JsonObject(mapOf("status" to JsonPrimitive(status))))
    suspend fun uninstallApp(installId: Long): LifecycleResult = delete("apps/installs/$installId")
    suspend fun installApp(manifestUrl: String, projectId: String): InstallResult = post(
        "apps/install",
        JsonObject(mapOf(
            "manifest_url" to JsonPrimitive(manifestUrl),
            "project_id" to JsonPrimitive(projectId),
            "config" to JsonObject(emptyMap()),
            "upgrade_policy" to JsonPrimitive("manual"),
            "bindings" to JsonObject(emptyMap()),
        )),
    )

    suspend fun nativeSurface(app: InstalledApp, descriptor: NativeSurfaceDescriptor, projectId: String): NativeSurface {
        require(descriptor.supportsProjectApp && descriptor.entry.startsWith("/ui/") && !descriptor.entry.contains(".."))
        return get("apps/${app.name}${descriptor.entry}?project_id=${encode(projectId)}")
    }

    suspend fun nativeDashboardWidgetSurface(
        appName: String,
        renderer: DashboardNativeRenderer,
        projectId: String,
    ): NativeSurface {
        require(renderer.schema == "apteva-native-surface/v1" && renderer.entry.startsWith("/ui/") && !renderer.entry.contains(".."))
        val surface: NativeSurface = get("apps/$appName${renderer.entry}?project_id=${encode(projectId)}")
        require(surface.schema == renderer.schema && surface.context.scope == "project" && surface.presentation == "widget")
        return surface
    }

    suspend fun nativeJson(
        appName: String,
        projectId: String,
        path: String,
        query: Map<String, String> = emptyMap(),
        method: String = "GET",
        body: JsonObject? = null,
    ): JsonElement {
        require(path.startsWith("/") && !path.contains("..") && !path.contains("://"))
        val suffix = buildList {
            add("project_id=${encode(projectId)}")
            query.forEach { (key, value) -> add("${encode(key)}=${encode(value)}") }
        }.joinToString("&")
        return decode(execute(method, "apps/$appName$path?$suffix", body?.toString()))
    }

    suspend fun download(appName: String, projectId: String, path: String): Pair<ByteArray, String?> {
        val response = executeResponse("GET", "apps/$appName$path?project_id=${encode(projectId)}")
        response.use { return (it.body?.bytes() ?: byteArrayOf()) to it.header("Content-Type") }
    }

    fun eventStream(path: String): Flow<SseEvent> = callbackFlow {
        val url = "$baseUrl/api/$path".toHttpUrlOrNull()
        if (url == null) {
            close(ApiException("Invalid realtime URL."))
            return@callbackFlow
        }
        val request = Request.Builder().url(url)
            .header("Accept", "text/event-stream")
            .header("Cache-Control", "no-cache")
            .header("Accept-Encoding", "identity")
            .apply { bearerToken?.takeIf(String::isNotBlank)?.let { header("Authorization", "Bearer $it") } }
            .build()
        val streamClient = client.newBuilder().readTimeout(0, TimeUnit.MILLISECONDS).build()
        val call = streamClient.newCall(request)
        val job = launch(Dispatchers.IO) {
            try {
                call.execute().use { response ->
                    if (!response.isSuccessful) throw ApiException("Realtime stream returned HTTP ${response.code}.", response.code)
                    trySend(SseEvent(null, "__apteva_open", "{}"))
                    val source = response.body?.source() ?: throw ApiException("Realtime stream returned no body.")
                    var id: String? = null
                    var name: String? = null
                    val data = mutableListOf<String>()
                    fun emitFrame() {
                        if (data.isNotEmpty()) trySend(SseEvent(id, name, data.joinToString("\n")))
                        id = null; name = null; data.clear()
                    }
                    while (isActive && !source.exhausted()) {
                        val line = source.readUtf8Line() ?: break
                        when {
                            line.isEmpty() -> emitFrame()
                            line.startsWith(":") -> Unit
                            line.startsWith("id:") -> id = line.removePrefix("id:").trim()
                            line.startsWith("event:") -> name = line.removePrefix("event:").trim()
                            line.startsWith("data:") -> data += line.removePrefix("data:").removePrefix(" ")
                        }
                    }
                    emitFrame()
                }
                close()
            } catch (error: Throwable) {
                if (isActive) close(error)
            }
        }
        awaitClose { call.cancel(); job.cancel() }
    }

    @PublishedApi
    internal inline fun <reified T> decode(raw: String): T = try {
        json.decodeFromString(raw)
    } catch (error: Exception) {
        throw ApiException("This server returned an incompatible response: ${error.message}")
    }

    @PublishedApi
    internal suspend fun execute(
        method: String,
        path: String,
        body: String? = null,
        headers: Map<String, String> = emptyMap(),
    ): String = executeResponse(method, path, body, headers).use { response -> response.body?.string().orEmpty() }

    private suspend fun executeResponse(
        method: String,
        path: String,
        body: String? = null,
        headers: Map<String, String> = emptyMap(),
    ) = withContext(Dispatchers.IO) {
        val separator = if ('?' in path) '&' else '?'
        val url = "$baseUrl/api/$path".toHttpUrlOrNull() ?: throw ApiException("Invalid server URL.")
        val builder = Request.Builder().url(url).header("Accept", "application/json")
        bearerToken?.takeIf(String::isNotBlank)?.let { builder.header("Authorization", "Bearer $it") }
        headers.forEach { (name, value) -> builder.header(name, value) }
        val requestBody = (body ?: "{}").toRequestBody(jsonType)
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post(requestBody)
            "PUT" -> builder.put(requestBody)
            "PATCH" -> builder.patch(requestBody)
            "DELETE" -> builder.delete()
        }
        val response = try { client.newCall(builder.build()).execute() }
        catch (error: IOException) { throw ApiException("Could not reach this Apteva server: ${error.message}") }
        if (!response.isSuccessful) {
            val status = response.code
            val raw = response.body?.string().orEmpty()
            response.close()
            val message = runCatching {
                val obj = json.parseToJsonElement(raw).jsonObject
                (obj["error"] as? JsonPrimitive)?.contentOrNull
                    ?: (obj["message"] as? JsonPrimitive)?.contentOrNull
            }.getOrNull() ?: raw.takeIf { it.isNotBlank() } ?: "Server returned HTTP $status."
            throw ApiException(if (status == 401) "The username or password is incorrect, or the session expired." else message, status)
        }
        response
    }

    private fun encode(value: String): String = java.net.URLEncoder.encode(value, Charsets.UTF_8.name())
}
