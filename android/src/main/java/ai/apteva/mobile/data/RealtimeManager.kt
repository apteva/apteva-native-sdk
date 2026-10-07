package ai.apteva.mobile.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class RealtimeManager(private val scope: CoroutineScope) {
    private val _projectState = MutableStateFlow(RealtimeConnectionState.Disconnected)
    val projectState: StateFlow<RealtimeConnectionState> = _projectState.asStateFlow()
    private val _userState = MutableStateFlow(RealtimeConnectionState.Disconnected)
    val userState: StateFlow<RealtimeConnectionState> = _userState.asStateFlow()
    private val _telemetry = MutableStateFlow<Map<Long, List<TelemetryEvent>>>(emptyMap())
    val telemetry: StateFlow<Map<Long, List<TelemetryEvent>>> = _telemetry.asStateFlow()
    private val _statusRevision = MutableStateFlow(0L)
    val statusRevision: StateFlow<Long> = _statusRevision.asStateFlow()
    private val _inboxRevision = MutableStateFlow(0L)
    val inboxRevision: StateFlow<Long> = _inboxRevision.asStateFlow()
    private val _chatRevision = MutableStateFlow(0L)
    val chatRevision: StateFlow<Long> = _chatRevision.asStateFlow()
    private val _unreadCount = MutableStateFlow(0)
    val unreadCount: StateFlow<Int> = _unreadCount.asStateFlow()
    private val _appEventRevision = MutableStateFlow(0L)
    val appEventRevision: StateFlow<Long> = _appEventRevision.asStateFlow()
    private val _lastAppEvent = MutableStateFlow<AppEventEnvelope?>(null)
    val lastAppEvent: StateFlow<AppEventEnvelope?> = _lastAppEvent.asStateFlow()

    private var projectJob: Job? = null
    private var appEventJob: Job? = null
    private var userJob: Job? = null
    private var projectScope: String? = null
    private var userScope: String? = null

    fun connect(client: ApiClient, projectId: String) {
        val nextProjectScope = "${client.baseUrl}|$projectId"
        if (projectScope != nextProjectScope || projectJob?.isActive != true || appEventJob?.isActive != true) {
            projectJob?.cancel()
            appEventJob?.cancel()
            projectScope = nextProjectScope
            _telemetry.value = emptyMap()
            projectJob = scope.launch { runProject(client, projectId, nextProjectScope) }
            appEventJob = scope.launch { runAppEvents(client, projectId, nextProjectScope) }
        }
        val nextUserScope = "${client.baseUrl}|$projectId"
        if (userScope != nextUserScope || userJob?.isActive != true) {
            userJob?.cancel()
            userScope = nextUserScope
            userJob = scope.launch { runUser(client, projectId, nextUserScope) }
            scope.launch { refreshUnread(client, projectId) }
        }
    }

    fun disconnect() {
        projectJob?.cancel(); appEventJob?.cancel(); userJob?.cancel()
        projectJob = null; appEventJob = null; userJob = null
        projectScope = null; userScope = null
        _projectState.value = RealtimeConnectionState.Disconnected
        _userState.value = RealtimeConnectionState.Disconnected
        _telemetry.value = emptyMap()
        _unreadCount.value = 0
        _lastAppEvent.value = null
    }

    private suspend fun runAppEvents(client: ApiClient, projectId: String, expectedScope: String) {
        var retry = 500L
        var cursor: String? = null
        while (scope.isActive && projectScope == expectedScope) {
            val suffix = cursor?.let { "&since=${java.net.URLEncoder.encode(it, "UTF-8")}" }.orEmpty()
            try {
                client.eventStream("app-events/_all?project_id=${java.net.URLEncoder.encode(projectId, "UTF-8")}$suffix")
                    .collect { event ->
                        if (event.name != "__apteva_open") {
                            if (!event.id.isNullOrBlank()) cursor = event.id
                            runCatching { ApiClient.json.decodeFromString<AppEventEnvelope>(event.data) }.onSuccess {
                                _lastAppEvent.value = it
                                _appEventRevision.value += 1
                            }
                        }
                    }
                retry = 500
            } catch (_: Throwable) {
                if (projectScope != expectedScope) return
            }
            delay(retry); retry = (retry * 2).coerceAtMost(30_000)
        }
    }

    suspend fun refreshUnread(client: ApiClient, projectId: String) {
        runCatching { client.unreadConversations(projectId) }.onSuccess { rows ->
            _unreadCount.value = rows.count { it.latestRole == "agent" && it.latestId > it.lastSeenId }
        }
    }

    private suspend fun runProject(client: ApiClient, projectId: String, expectedScope: String) {
        var retry = 500L
        var cursor: String? = null
        var opened = false
        while (scope.isActive && projectScope == expectedScope) {
            _projectState.value = if (opened) RealtimeConnectionState.Reconnecting else RealtimeConnectionState.Connecting
            val suffix = cursor?.let { "&since=${java.net.URLEncoder.encode(it, "UTF-8")}" }.orEmpty()
            try {
                client.eventStream("telemetry/stream?all=1&project_id=${java.net.URLEncoder.encode(projectId, "UTF-8")}$suffix")
                    .collect { event ->
                        if (event.name == "__apteva_open") {
                            opened = true; retry = 500; _projectState.value = RealtimeConnectionState.Connected
                        } else {
                            if (!event.id.isNullOrBlank()) cursor = event.id
                            runCatching { ApiClient.json.decodeFromString<TelemetryEvent>(event.data) }
                                .onSuccess(::mergeTelemetry)
                        }
                    }
            } catch (_: Throwable) {
                if (projectScope != expectedScope) return
                _projectState.value = RealtimeConnectionState.Reconnecting
            }
            delay(retry); retry = (retry * 2).coerceAtMost(30_000)
        }
    }

    private suspend fun runUser(client: ApiClient, projectId: String, expectedScope: String) {
        var retry = 500L
        var opened = false
        while (scope.isActive && userScope == expectedScope) {
            _userState.value = if (opened) RealtimeConnectionState.Reconnecting else RealtimeConnectionState.Connecting
            try {
                client.eventStream("apps/channel-chat/stream?scope=user").collect { event ->
                    if (event.name == "__apteva_open" || event.name == "ready") {
                        opened = true; retry = 500; _userState.value = RealtimeConnectionState.Connected
                    } else {
                        runCatching { ApiClient.json.decodeFromString<ConversationMessage>(event.data) }.onSuccess { message ->
                            _chatRevision.value += 1
                            val names = message.components.orEmpty().map { it.name }.toSet()
                            if ("status-card" in names) _statusRevision.value += 1
                            if (names.any { it in setOf("approval-card", "report-card", "alert-card") }) _inboxRevision.value += 1
                            scope.launch { refreshUnread(client, projectId) }
                        }
                    }
                }
            } catch (_: Throwable) {
                if (userScope != expectedScope) return
                _userState.value = RealtimeConnectionState.Reconnecting
            }
            delay(retry); retry = (retry * 2).coerceAtMost(30_000)
        }
    }

    private fun mergeTelemetry(event: TelemetryEvent) {
        _telemetry.update { current ->
            val rows = (current[event.instanceId].orEmpty().filterNot { it.id == event.id } + event)
                .sortedByDescending { it.time }
                .take(120)
            current + (event.instanceId to rows)
        }
    }
}
