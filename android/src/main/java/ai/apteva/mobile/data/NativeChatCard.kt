package ai.apteva.mobile.data

import java.time.Instant
import kotlinx.serialization.json.*

/** Shared card semantics. Rendering and input remain native to the host. */
data class NativeChatCard(val raw: JsonObject, val index: Int = 0) {
    val componentId = raw.text("id")
    val app = raw.text("app")
    val name = raw.text("name")
    val key = "$index:$componentId:$app/$name"
    val props = raw["props"] as? JsonObject ?: JsonObject(emptyMap())
    val interaction = raw["interaction"] as? JsonObject
    val supported = raw["version"] == null || (raw["version"] as? JsonPrimitive)?.intOrNull == 1
    val kind = when {
        !supported -> "unsupported"
        app in setOf("conversations", "channel-chat") && name in setOf("alert-card", "approval-card", "report-card") -> name.removeSuffix("-card")
        interaction != null -> "interaction"
        else -> "unsupported"
    }
    val title get() = props.text("title")
    val detail get() = props.text(when(kind) { "alert" -> "text"; "report" -> "summary"; else -> "body" })
    val severity get() = props.text("severity").ifBlank { "info" }
    val label get() = when(kind) {
        "alert" -> when(severity) { "error" -> "Error"; "warn", "warning" -> "Warning"; else -> "Info" }
        "approval" -> "Approval requested"
        "report" -> "Report"
        "interaction" -> "Question"
        else -> "Additional content"
    }
    val status get() = (if(kind == "approval") props else interaction)?.text("status").orEmpty().ifBlank { "pending" }
    val actions get() = ((if(kind == "approval") props else interaction)?.get("actions") as? JsonArray).orEmpty()
        .mapNotNull { it as? JsonObject }.filter { it.text("id").isNotBlank() }
    val fields get() = (interaction?.get("fields") as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
    val sections get() = (props["sections"] as? JsonArray).orEmpty()
    val savedValues get() = interaction?.get("values") as? JsonObject ?: JsonObject(emptyMap())
    val decisionLabel: String get() {
        val selected = if(kind == "approval") status else interaction?.text("action_id")
        actions.firstOrNull { it.text("id") == selected }?.let { return "Decision: ${it.text("label").ifBlank { selected.orEmpty() }}" }
        return when(status) { "approve", "approved" -> "Approved"; "deny", "denied" -> "Declined"; "pending" -> "Expired"; else -> status.replaceFirstChar { it.uppercase() } }
    }
    fun pending(now: Instant = Instant.now()): Boolean {
        if(!supported || status != "pending" || kind !in setOf("approval", "interaction")) return false
        val expires = interaction?.text("expires_at").orEmpty()
        return expires.isEmpty() || runCatching { Instant.parse(expires).isAfter(now) }.getOrDefault(false)
    }
    fun actionBody(messageId: JsonElement, action: JsonObject, values: JsonObject, note: String): JsonObject {
        require(pending() && actions.any { it.text("id") == action.text("id") }) { "This request has changed or is no longer available." }
        if(kind == "approval") return buildJsonObject { put("message_id", messageId); put("action_id", action.text("id")); put("note", note) }
        require(componentId.isNotBlank()) { "This request is unavailable." }
        if((action["cancel"] as? JsonPrimitive)?.booleanOrNull != true) {
            for(field in fields) require(validField(field, values[field.text("id")])) { "Check ${field.text("label")} before continuing." }
        }
        return buildJsonObject { put("message_id", messageId); put("component_id", componentId); put("action_id", action.text("id")); put("values", values) }
    }
}

fun JsonObject.text(key: String): String = (this[key] as? JsonPrimitive)?.contentOrNull.orEmpty()
fun validField(field: JsonObject, value: JsonElement?): Boolean {
    val required = (field["required"] as? JsonPrimitive)?.booleanOrNull == true
    if(value == null || value == JsonNull || (value as? JsonPrimitive)?.contentOrNull?.isBlank() == true || (value as? JsonArray)?.isEmpty() == true) return !required
    val options = (field["options"] as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.text("id") }
    return when(field.text("type")) {
        "multichoice" -> value is JsonArray && value.all { (it as? JsonPrimitive)?.contentOrNull in options }
        "choice" -> (value as? JsonPrimitive)?.contentOrNull?.let { it.length <= 8000 && ((field["allow_custom"] as? JsonPrimitive)?.booleanOrNull == true || it in options) } == true
        "text", "textarea", "" -> value is JsonPrimitive && value.isString && value.content.length <= 8000
        else -> false
    }
}
fun nativeChatCards(message: JsonObject, selector: String = "$.components"): List<NativeChatCard> =
    (nativeChatSelect(message, selector) as? JsonArray).orEmpty().mapIndexedNotNull { index, value ->
        val component = value as? JsonObject ?: return@mapIndexedNotNull null
        if(component.text("app") == "conversations" && component.text("name") in setOf("reply-suggestion", "reply-suggestions")) null else NativeChatCard(component, index)
    }
fun nativeChatBody(body: String, cards: List<NativeChatCard>): String = body.trim().takeUnless { text ->
    cards.any { it.kind != "unsupported" && text in listOf(it.title, it.detail, listOf(it.title, it.detail).filter(String::isNotEmpty).joinToString("\n"),
        if(it.kind == "approval") "Approval requested: " + it.title else "",
        if(it.kind == "report") "Report: " + it.title else "") }
}.orEmpty()
fun nativeChatSelect(root: JsonElement, selector: String): JsonElement? = when {
    selector == "$" -> root
    !selector.startsWith("$.") -> null
    else -> selector.removePrefix("$.").split('.').fold(root as JsonElement?) { current, key -> (current as? JsonObject)?.get(key) }
}

fun nativeChatMergingSnapshot(snapshot: List<JsonObject>, live: List<JsonObject>, baseline: List<JsonObject>, idSelector: String = "$.id"): List<JsonObject> {
    fun id(item: JsonObject) = (nativeChatSelect(item, idSelector) as? JsonPrimitive)?.contentOrNull.orEmpty()
    val before = baseline.associateBy(::id)
    val current = live.associateBy(::id)
    val result = linkedMapOf<String, JsonObject>()
    live.filter { id(it).isNotBlank() }.forEach { result[id(it)] = it }
    snapshot.filter { id(it).isNotBlank() }.forEach { server ->
        val local = current[id(server)]
        val serverRevision = (server["revision"] as? JsonPrimitive)?.longOrNull
        val liveRevision = (local?.get("revision") as? JsonPrimitive)?.longOrNull
        val newer = serverRevision != null && liveRevision != null && serverRevision > liveRevision
        if(local == null || local == before[id(server)] || newer) result[id(server)] = server
    }
    val rows = result.values.toList()
    return if(rows.all { id(it).toLongOrNull() != null }) rows.sortedBy { id(it).toLong() } else rows
}
