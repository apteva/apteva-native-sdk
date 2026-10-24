import Foundation
import XCTest
@testable import AptevaNativeSDK

final class UserNotificationTests: XCTestCase {
    private var fixture: Data {
        get throws {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            return try Data(contentsOf: root.appendingPathComponent("contract/fixtures/user-notification.json"))
        }
    }
    private let base = URL(string: "https://example.test")!

    override func tearDown() { NotificationURLProtocol.handler = nil; super.tearDown() }

    func testGenericAndLegacyPayloadsUseSeparateIDNamespaces() throws {
        let generic = try XCTUnwrap(AptevaPushDestination(userInfo: ["data": ["type": "notification", "item_id": "901", "instance_ref": "instance-a", "project_id": "project-b"]]))
        XCTAssertEqual(generic.kind, "notification")
        XCTAssertEqual(generic.itemID, 901)
        XCTAssertEqual(generic.instanceRef, "instance-a")
        for kind in ["approval", "report", "alert"] {
            XCTAssertEqual(AptevaPushDestination(userInfo: ["type": kind, "item_id": 42])?.itemID, 42)
        }
        for id in ["", "0", "-3", "NaN", "1.5", "9223372036854775808"] {
            XCTAssertNil(AptevaPushDestination(userInfo: ["type": "notification", "item_id": id]))
        }
        XCTAssertNil(AptevaPushDestination(userInfo: ["type": "test", "item_id": "901"]))
        XCTAssertNil(AptevaPushDestination(userInfo: ["type": "notification", "item_id": true]))
    }

    func testNotificationLinkUsesMessageIDNotNotificationID() throws {
        let item = try JSONDecoder().decode(AptevaUserNotification.self, from: fixture)
        let link = try item.link(baseURL: base)
        XCTAssertEqual(link.conversationID, "thread-7")
        XCTAssertEqual(link.messageID, "42")
        XCTAssertEqual(item.id, 901)
    }

    func testOldLinksWithoutMessageIDStillOpenConversation() throws {
        var object = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
        object["url"] = "/apps/conversations/page?project_id=project-b&install_id=72&chat=thread-7"
        let item = try JSONDecoder().decode(AptevaUserNotification.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(try item.link(baseURL: base).conversationID, "thread-7")
        XCTAssertNil(try item.link(baseURL: base).messageID)
    }

    func testForeignOriginWrongScopeAndAmbiguousLinksAreRejected() throws {
        var object = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
        for link in [
            "https://evil.test/apps/conversations/page?project_id=project-b&install_id=72&chat=thread-7",
            "/apps/conversations/page?project_id=other&install_id=72&chat=thread-7",
            "/apps/conversations/page?project_id=project-b&install_id=99&chat=thread-7",
            "/apps/tasks/page?project_id=project-b&install_id=72&chat=thread-7",
            "/apps/conversations/page?project_id=project-b&install_id=72&chat=a&chat=b",
            "/apps/conversations/page?project_id=project-b&install_id=72&message_id=-1"
        ] {
            object["url"] = link
            let item = try JSONDecoder().decode(AptevaUserNotification.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try item.link(baseURL: base), link)
        }
    }

    func testOlderPushConfigRemainsCompatible() throws {
        let config = try JSONDecoder().decode(AptevaMobilePushConfig.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertFalse(config.supportsAppNotifications)
        XCTAssertNil(config.instanceRef)
    }

    func testNotificationFetchSnapshotAndBoundedAcknowledgementUseBearer() async throws {
        let bytes = try fixture
        NotificationURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer device-test")
            let data: Data
            switch (request.httpMethod, request.url!.path) {
            case ("GET", "/api/notifications/901"): data = bytes
            case ("PATCH", "/api/notifications/901"):
                let body = try Self.body(request)
                XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: Bool], ["read": true])
                data = Data(#"{"ok":true}"#.utf8)
            case ("GET", "/api/notifications"):
                data = Data(#"{"items":[],"unread_count":3,"tab_count":2,"next_before":0}"#.utf8)
            default: XCTFail("Unexpected request: \(request)"); data = Data()
            }
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }
        let client = AptevaAPIClient(baseURL: base, bearerToken: "device-test", protocolClasses: [NotificationURLProtocol.self])
        let notification = try await client.userNotification(id: 901)
        XCTAssertEqual(notification.id, 901)
        try await client.markUserNotificationRead(id: 901)
        let snapshot = try await client.userNotifications()
        XCTAssertEqual(snapshot.unreadCount, 3)
    }

    func testNativeInstallScopeCannotBeOverriddenBySurfaceQuery() throws {
        let client = AptevaAPIClient(baseURL: base).scopedToAppInstallation(72)
        let url = try XCTUnwrap(client.nativeAppURL(appName: "conversations", projectID: "project-b", path: "/messages", query: ["project_id": "wrong", "install_id": "99", "chat_id": "thread-7"]))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.filter { $0.name == "install_id" }.map(\.value), ["72"])
        XCTAssertEqual(items.filter { $0.name == "project_id" }.map(\.value), ["project-b"])
    }

    @MainActor
    func testNotificationFindsOlderMessageAndPreservesHistoryOrder() async throws {
        let latest = NativeChatHistoryPage(messages: [row("44"), row("45")], nextCursor: "44")
        var cursors: [String] = []
        let resolved = try await nativeChatNotificationHistory(initial: latest, targetMessageID: "42", idSelector: "$.id") { cursor in
            cursors.append(cursor)
            return NativeChatHistoryPage(messages: [self.row("41"), self.row("42"), self.row("43")], nextCursor: "41")
        }
        XCTAssertEqual(cursors, ["44"])
        XCTAssertEqual(resolved.messages.map { nativeChatMessageID($0, selector: "$.id") }, ["41", "42", "43", "44", "45"])
    }

    @MainActor
    func testMissingTargetAndRepeatingCursorFailInsteadOfAcknowledging() async {
        for cursor in [nil, "repeat"] as [String?] {
            do {
                _ = try await nativeChatNotificationHistory(
                    initial: NativeChatHistoryPage(messages: [row("44")], nextCursor: cursor),
                    targetMessageID: "42", idSelector: "$.id"
                ) { _ in NativeChatHistoryPage(messages: [self.row("43")], nextCursor: cursor) }
                XCTFail("Missing notification target was treated as opened")
            } catch { XCTAssertTrue(error.localizedDescription.contains("no longer available")) }
        }
    }

    @MainActor
    func testConversationOnlyLinkDoesNotFetchOlderHistory() async throws {
        _ = try await nativeChatNotificationHistory(
            initial: NativeChatHistoryPage(messages: [row("44")], nextCursor: "44"),
            targetMessageID: nil, idSelector: "$.id"
        ) { _ in XCTFail("An older link should open the conversation directly"); return NativeChatHistoryPage(messages: [], nextCursor: nil) }
    }

    private func row(_ id: String) -> NativeJSONValue { .object(["id": .string(id)]) }

    func testReconnectSnapshotDoesNotMoveOlderFocusedHistoryAfterLatestPage() {
        let history = [row("41"), row("42"), row("43"), row("44"), row("45")]
        let merged = nativeChatMergingSnapshot([row("44"), row("45")], preserving: history, idSelector: "$.id")
        XCTAssertEqual(merged.map { nativeChatMessageID($0, selector: "$.id") }, ["41", "42", "43", "44", "45"])
    }

    private static func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}

private final class NotificationURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
