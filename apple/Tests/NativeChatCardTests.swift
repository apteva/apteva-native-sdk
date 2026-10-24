import Foundation
import XCTest
@testable import AptevaNativeSDK

final class NativeChatCardTests: XCTestCase {
    func testSharedWireFixtureKeepsAppleAndAndroidCardSemanticsAligned() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(NativeJSONValue.self, from: Data(contentsOf: root.appendingPathComponent("contract/fixtures/conversation-cards.json")))
        let messages = try XCTUnwrap(fixture.value(at: "$.messages")?.arrayValue)
        let cards = messages.flatMap { nativeChatCards(in: $0) }
        XCTAssertEqual(cards.map(\.kind), [.alert, .approval, .report, .interaction])
        XCTAssertEqual(cards[1].actions.map(\.id), ["keep", "delete"])
        XCTAssertEqual(cards[3].fields.first?.allowCustom, true)
        XCTAssertEqual(nativeChatBody("Approval requested: Keep the list?", beside: [cards[1]]), "")
    }

    private func json(_ text: String) throws -> NativeJSONValue { try JSONDecoder().decode(NativeJSONValue.self, from: Data(text.utf8)) }
    private func card(_ text: String) throws -> NativeChatCard { NativeChatCard(try json(text)) }

    func testRealInfoAlertIsAVisibleCardWithoutDuplicateBody() throws {
        let message = try json(#"{"role":"agent","content":"Second test alert requested by the user. No action is required.","components":[{"id":"alert","version":1,"app":"conversations","name":"alert-card","props":{"severity":"info","text":"Second test alert requested by the user. No action is required."}}]}"#)
        let cards = nativeChatCards(in: message)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].kind, .alert)
        XCTAssertEqual(cards[0].label, "Info")
        XCTAssertEqual(nativeChatBody(message.value(at: "$.content")!.scalarString, beside: cards), "")
        XCTAssertEqual(nativeChatBody("Extra context", beside: cards), "Extra context")
    }

    func testSeverityAndUnsupportedVersionsDoNotInventActions() throws {
        for (severity, label) in [("warn", "Warning"), ("error", "Error"), ("unknown", "Info")] {
            XCTAssertEqual(try card("{\"app\":\"conversations\",\"name\":\"alert-card\",\"props\":{\"severity\":\"\(severity)\"}}").label, label)
        }
        let future = try card(#"{"version":2,"app":"conversations","name":"approval-card","props":{"status":"pending"}}"#)
        XCTAssertEqual(future.kind, .unsupported)
        XCTAssertFalse(future.isPending())
        XCTAssertEqual(try card(#"{"app":"other","name":"alert-card","props":{}}"#).kind, .unsupported)
    }

    func testLegacyApprovalUsesExactCustomVerdictAndNoteEvenWithInteraction() throws {
        let approval = try card(#"{"id":"approval","app":"conversations","name":"approval-card","props":{"status":"pending","actions":[{"id":"keep","label":"Keep list"}]},"interaction":{"status":"pending","fields":[{"id":"note","required":true}]}}"#)
        let body = try approval.actionBody(messageID: .number(42), action: approval.actions[0], values: [:], note: "Keep our data")
        XCTAssertEqual(body, ["message_id": .number(42), "action_id": .string("keep"), "note": .string("Keep our data")])
        XCTAssertNil(body["component_id"])
        XCTAssertEqual(nativeChatBody("Approval requested: Keep our list?", beside: [try card(#"{"app":"conversations","name":"approval-card","props":{"title":"Keep our list?"}}"#)]), "")
    }

    func testResolvedApprovalShowsChosenLabelAndCannotSubmitAgain() throws {
        let approval = try card(#"{"app":"conversations","name":"approval-card","props":{"status":"keep","actions":[{"id":"keep","label":"Keep list"}],"note":"Our data"}}"#)
        XCTAssertEqual(approval.decisionLabel, "Decision: Keep list")
        XCTAssertFalse(approval.isPending())
        XCTAssertThrowsError(try approval.actionBody(messageID: .number(42), action: approval.actions[0], values: [:], note: ""))
    }

    func testInteractionValidationCancellationAndComponentID() throws {
        let question = try card(#"{"id":"tone","app":"conversations","name":"question-card","interaction":{"status":"pending","fields":[{"id":"tone","type":"choice","label":"Tone","required":true,"options":[{"id":"brief","label":"Brief"}]}],"actions":[{"id":"submit","label":"Submit"},{"id":"skip","label":"Skip","cancel":true}]}}"#)
        XCTAssertThrowsError(try question.actionBody(messageID: .number(1), action: question.actions[0], values: [:], note: ""))
        XCTAssertThrowsError(try question.actionBody(messageID: .number(1), action: question.actions[0], values: ["tone": .string("invalid")], note: ""))
        let body = try question.actionBody(messageID: .number(1), action: question.actions[0], values: ["tone": .string("brief")], note: "")
        XCTAssertEqual(body["component_id"], .string("tone"))
        XCTAssertEqual(body["values"], .object(["tone": .string("brief")]))
        XCTAssertNoThrow(try question.actionBody(messageID: .number(1), action: question.actions[1], values: [:], note: ""))
        XCTAssertEqual(question.fields[0].display(.string("brief")), "Brief")
    }

    func testExpiredQuestionDoesNotOfferActions() throws {
        let question = try card(#"{"id":"q","name":"question-card","interaction":{"status":"pending","expires_at":"2020-01-01T00:00:00Z","actions":[{"id":"submit"}]}}"#)
        XCTAssertFalse(question.isPending())
        XCTAssertEqual(question.decisionLabel, "Expired")
    }

    func testReportRetainsSectionsAndSystemCards() throws {
        let message = try json(#"{"role":"system","components":[{"app":"conversations","name":"report-card","props":{"title":"Daily report","summary":"All healthy","period":"Today","sections":[{"title":"Evidence","body":"Checks passed"}]}}]}"#)
        let report = nativeChatCards(in: message)[0]
        XCTAssertEqual(report.kind, .report)
        XCTAssertEqual(report.sections.count, 1)
        XCTAssertEqual(report.text("period"), "Today")
        XCTAssertEqual(nativeChatBody("Report: Daily report", beside: [report]), "")
    }

    func testOlderChatMappingAndSuggestionsRemainCompatible() throws {
        let mapping = try JSONDecoder().decode(DeclaredSurfaceChatMessageMapping.self, from: Data(#"{"id":"$.id","conversation_id":"$.conversation_id","body":"$.content"}"#.utf8))
        XCTAssertNil(mapping.components)
        let message = try json(#"{"components":[null,{"app":"conversations","name":"reply-suggestions","props":{}},{"app":"other","name":"reply-suggestions","props":{}}]}"#)
        XCTAssertEqual(nativeChatCards(in: message).count, 1)
    }

    func testReconnectReplacesStalePendingDecisionButKeepsConcurrentNewerEvent() throws {
        let pending = try json(#"{"id":42,"revision":1,"status":"pending"}"#)
        let resolved = try json(#"{"id":42,"revision":2,"status":"approved"}"#)
        XCTAssertEqual(nativeChatMergingSnapshot([resolved], preserving: [pending], idSelector: "$.id", baseline: [pending]), [resolved])
        XCTAssertEqual(nativeChatMergingSnapshot([pending], preserving: [resolved], idSelector: "$.id", baseline: [pending]), [resolved])
        XCTAssertEqual(nativeChatMergingSnapshot([resolved], preserving: [pending], idSelector: "$.id"), [resolved])
    }
}
