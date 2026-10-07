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
import java.time.Instant
import java.util.UUID

data class ChatRealtimeState(
    val conversation: Conversation? = null,
    val messages: List<ConversationMessage> = emptyList(),
    val streamingText: String = "",
    val streamingPhase: String? = null,
    val awaitingResponse: Boolean = false,
    val responseStartedAt: String? = null,
    val connection: RealtimeConnectionState = RealtimeConnectionState.Disconnected,
    val loading: Boolean = false,
    val error: String? = null,
)

class ChatRealtimeCoordinator(private val scope: CoroutineScope) {
    private val _state = MutableStateFlow(ChatRealtimeState())
    val state: StateFlow<ChatRealtimeState> = _state.asStateFlow()
    private var streamJob: Job? = null
    private var reconcileJob: Job? = null
    private var client: ApiClient? = null
    private var highestId = 0L
    private var optimisticId = -1L
    private val settledCalls = mutableSetOf<String>()

    fun activate(conversation: Conversation, nextClient: ApiClient) {
        if (_state.value.conversation?.id == conversation.id && streamJob?.isActive == true) return
        disconnect(sendPresence = true)
        client = nextClient
        highestId = 0
        optimisticId = -1
        settledCalls.clear()
        _state.value = ChatRealtimeState(
            conversation = conversation,
            loading = true,
            connection = RealtimeConnectionState.Connecting,
        )
        streamJob = scope.launch {
            runCatching { nextClient.conversationMessages(conversation.id) }
                .onSuccess { merge(it); markSeen(); _state.update { state -> state.copy(loading = false, error = null) } }
                .onFailure { error -> _state.update { state -> state.copy(loading = false, error = error.message) } }
            runStream(conversation, nextClient)
        }
    }

    fun disconnect(sendPresence: Boolean = true) {
        val oldClient = client
        val oldChat = _state.value.conversation?.id
        streamJob?.cancel(); reconcileJob?.cancel()
        streamJob = null; reconcileJob = null
        if (sendPresence && oldClient != null && oldChat != null) {
            scope.launch { runCatching { oldClient.updateConversationPresence(oldChat, false) } }
        }
        _state.value = ChatRealtimeState()
    }

    suspend fun send(content: String, attachments: List<ConversationAttachment>) {
        val nextClient = client ?: throw ApiException("The server connection is unavailable.")
        val conversation = _state.value.conversation ?: throw ApiException("Choose a conversation first.")
        val clientId = UUID.randomUUID().toString().lowercase()
        val optimistic = ConversationMessage(
            id = optimisticId--,
            chatId = conversation.id,
            role = "user",
            content = content,
            threadId = conversation.threadId,
            status = "sending",
            createdAt = Instant.now().toString(),
            attachments = attachments.ifEmpty { null },
            clientMessageId = clientId,
        )
        merge(optimistic)
        _state.update { it.copy(awaitingResponse = true, responseStartedAt = optimistic.createdAt, error = null) }
        try {
            merge(nextClient.sendConversationMessage(conversation.id, content, attachments, clientId))
        } catch (error: Throwable) {
            _state.update { state ->
                state.copy(messages = state.messages.filterNot { it.clientMessageId == clientId }, error = error.message)
            }
            throw error
        }
    }

    suspend fun markSeen() {
        val nextClient = client ?: return
        val chatId = _state.value.conversation?.id ?: return
        if (highestId > 0) runCatching { nextClient.markConversationSeen(chatId, highestId) }
    }

    private suspend fun runStream(conversation: Conversation, nextClient: ApiClient) {
        runCatching { nextClient.updateConversationPresence(conversation.id, true) }
        reconcileJob = scope.launch {
            while (isActive && _state.value.conversation?.id == conversation.id) {
                reconcile(conversation, nextClient)
                delay(5_000)
            }
        }
        var retry = 500L
        var opened = false
        while (scope.isActive && _state.value.conversation?.id == conversation.id) {
            _state.update { it.copy(connection = if (opened) RealtimeConnectionState.Reconnecting else RealtimeConnectionState.Connecting) }
            try {
                nextClient.eventStream("apps/channel-chat/stream?chat_id=${encode(conversation.id)}&since=$highestId")
                    .collect { event ->
                        if (event.name == "__apteva_open") {
                            opened = true; retry = 500
                            _state.update { it.copy(connection = RealtimeConnectionState.Connected, error = null) }
                        } else if (event.name == "stream") {
                            runCatching { ApiClient.json.decodeFromString<ChatStreamFrame>(event.data) }.onSuccess(::receive)
                        } else {
                            runCatching { ApiClient.json.decodeFromString<ConversationMessage>(event.data) }.onSuccess(::merge)
                            markSeen()
                        }
                    }
            } catch (_: Throwable) {
                if (_state.value.conversation?.id != conversation.id) return
                _state.update {
                    it.copy(
                        connection = RealtimeConnectionState.Reconnecting,
                        streamingText = "",
                        streamingPhase = null,
                        error = "Live updates paused. Reconnecting…",
                    )
                }
            }
            delay(retry); retry = (retry * 2).coerceAtMost(30_000)
        }
    }

    private suspend fun reconcile(conversation: Conversation, nextClient: ApiClient) {
        runCatching { nextClient.conversationMessages(conversation.id, highestId, 200) }
            .onSuccess { merge(it); markSeen() }
    }

    private fun receive(frame: ChatStreamFrame) {
        if (frame.callId in settledCalls) return
        if (frame.done) {
            settledCalls += frame.callId
            scope.launch {
                delay(1_500)
                _state.update { it.copy(streamingText = "", streamingPhase = null) }
            }
        } else {
            _state.update { it.copy(streamingText = frame.text, streamingPhase = frame.phase) }
        }
    }

    private fun merge(rows: List<ConversationMessage>) = rows.forEach(::merge)

    private fun merge(message: ConversationMessage) {
        _state.update { current ->
            val rows = current.messages
                .filterNot { it.id == message.id || (!message.clientMessageId.isNullOrBlank() && it.clientMessageId == message.clientMessageId) }
                .plus(message)
                .sortedWith(compareBy<ConversationMessage> { if (it.id < 0) Long.MAX_VALUE else it.id })
            if (message.id > 0) highestId = maxOf(highestId, message.id)
            when (message.role) {
                "user" -> current.copy(
                    messages = rows,
                    awaitingResponse = true,
                    responseStartedAt = message.createdAt,
                )
                "agent" -> current.copy(
                    messages = rows,
                    streamingText = "",
                    streamingPhase = null,
                    awaitingResponse = message.phase != "final",
                    responseStartedAt = if (message.phase == "final") null else current.responseStartedAt ?: message.createdAt,
                )
                else -> current.copy(messages = rows)
            }
        }
    }

    private fun encode(value: String): String = java.net.URLEncoder.encode(value, Charsets.UTF_8.name())
}
