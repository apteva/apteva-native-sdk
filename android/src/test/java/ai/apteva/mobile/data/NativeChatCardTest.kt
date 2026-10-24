package ai.apteva.mobile.data

import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class NativeChatCardTest {
    @Test fun sharedWireFixtureKeepsAppleAndAndroidCardSemanticsAligned() {
        val fixture = obj(java.io.File("../contract/fixtures/conversation-cards.json").readText())
        val cards = fixture["messages"]!!.jsonArray.flatMap { nativeChatCards(it.jsonObject) }
        assertEquals(listOf("alert", "approval", "report", "interaction"), cards.map { it.kind })
        assertEquals(listOf("keep", "delete"), cards[1].actions.map { it.text("id") })
        assertEquals("", nativeChatBody("Approval requested: Keep the list?", listOf(cards[1])))
    }

    private fun obj(json: String) = ApiClient.json.parseToJsonElement(json).jsonObject
    @Test fun realInfoAlertHasSeverityAndNoDuplicateText() {
        val message = obj("""{"role":"agent","content":"Second test alert requested by the user. No action is required.","components":[{"id":"alert","version":1,"app":"conversations","name":"alert-card","props":{"text":"Second test alert requested by the user. No action is required.","severity":"info"}}]}""")
        val cards = nativeChatCards(message)
        assertEquals("Info", cards.single().label)
        assertEquals("", nativeChatBody(message.text("content"), cards))
        assertEquals("Additional explanation", nativeChatBody("Additional explanation", cards))
    }
    @Test fun approvalKeepsCustomActionsAndLegacyPayload() {
        val card = NativeChatCard(obj("""{"id":"approval","app":"conversations","name":"approval-card","props":{"status":"pending","actions":[{"id":"keep","label":"Keep our list"}]},"interaction":{"status":"pending"}}"""))
        assertEquals(obj("""{"message_id":42,"action_id":"keep","note":"Preserve our data"}"""), card.actionBody(JsonPrimitive(42), card.actions[0], JsonObject(emptyMap()), "Preserve our data"))
        val resolved = card.copy(raw = JsonObject(card.raw + ("props" to JsonObject(card.props + ("status" to JsonPrimitive("keep"))))))
        assertFalse(resolved.pending())
        assertEquals("Decision: Keep our list", resolved.decisionLabel)
        assertThrows(IllegalArgumentException::class.java) { resolved.actionBody(JsonPrimitive(42), card.actions[0], JsonObject(emptyMap()), "") }
    }
    @Test fun questionsValidateRequiredChoicesButAllowCancel() {
        val card = NativeChatCard(obj("""{"id":"tone","app":"conversations","name":"question-card","interaction":{"status":"pending","fields":[{"id":"tone","label":"Tone","type":"choice","required":true,"options":[{"id":"brief","label":"Brief"}]}],"actions":[{"id":"submit","label":"Submit"},{"id":"skip","label":"Skip","cancel":true}]}}"""))
        assertThrows(IllegalArgumentException::class.java) { card.actionBody(JsonPrimitive(2), card.actions[0], JsonObject(emptyMap()), "") }
        val body = card.actionBody(JsonPrimitive(2), card.actions[0], obj("""{"tone":"brief"}"""), "")
        assertEquals("tone", body.text("component_id"))
        card.actionBody(JsonPrimitive(2), card.actions[1], JsonObject(emptyMap()), "")
    }
    @Test fun unknownVersionsExpiredAndUnknownAppsFailClosed() {
        val future = NativeChatCard(obj("""{"version":2,"app":"conversations","name":"approval-card","props":{"status":"pending"}}"""))
        assertEquals("unsupported", future.kind); assertFalse(future.pending())
        val expired = NativeChatCard(obj("""{"id":"q","interaction":{"status":"pending","expires_at":"2020-01-01T00:00:00Z"}}"""))
        assertFalse(expired.pending())
        assertEquals("unsupported", NativeChatCard(obj("""{"app":"other","name":"alert-card"}""")).kind)
    }
    @Test fun reportsAndLegacySurfaceRemainCompatible() {
        val report = NativeChatCard(obj("""{"app":"conversations","name":"report-card","props":{"title":"Daily report","summary":"All healthy","sections":[{"title":"Evidence","body":"Checks passed"}]}}"""))
        assertEquals(1, report.sections.size)
        val surface = ApiClient.json.decodeFromString<SurfaceSection>("""{"id":"chat","kind":"component","component":"chat/v1","chat":{"messages_source":"messages"}}""")
        assertEquals("chat/v1", surface.component)
        assertEquals("messages", surface.chat?.text("messages_source"))
        assertNull(ApiClient.json.decodeFromString<SurfaceSection>("""{"id":"files","kind":"collection"}""").chat)
    }
    @Test fun reconnectUsesServerDecisionUnlessANewerEventArrived() {
        val pending = obj("""{"id":42,"revision":1,"status":"pending"}""")
        val resolved = obj("""{"id":42,"revision":2,"status":"approved"}""")
        assertEquals(listOf(resolved), nativeChatMergingSnapshot(listOf(resolved), listOf(pending), listOf(pending)))
        assertEquals(listOf(resolved), nativeChatMergingSnapshot(listOf(pending), listOf(resolved), listOf(pending)))
    }
}
