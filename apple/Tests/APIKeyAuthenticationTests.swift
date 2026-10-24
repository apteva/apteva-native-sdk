import Foundation
import XCTest
@testable import AptevaNativeSDK
#if canImport(UIKit)
@testable import AptevaNativeUIKit
#endif

final class APIKeyAuthenticationTests: XCTestCase {
    func testContractVersionMatchesTheComposableChatRelease() {
        XCTAssertEqual(AptevaClientContract.version, "1.3.0")
    }

    func testServerURLNormalizationEnforcesTheSharedSecurityBoundary() throws {
        XCTAssertEqual(
            try AptevaAPIClient.normalizedServerURL(from: "example.apteva.test").absoluteString,
            "https://example.apteva.test"
        )
        XCTAssertThrowsError(try AptevaAPIClient.normalizedServerURL(from: "http://example.apteva.test"))
        XCTAssertThrowsError(try AptevaAPIClient.normalizedServerURL(from: "https://user:secret@example.apteva.test"))
        XCTAssertThrowsError(try AptevaAPIClient.normalizedServerURL(from: "https://example.apteva.test?token=secret"))
        XCTAssertThrowsError(try AptevaAPIClient.normalizedServerURL(from: "https://example.apteva.test/#fragment"))
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testBearerCredentialIsUsedForRESTRequests() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer sk-device-test"
            )
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (
                response,
                Data(#"{"user_id":7,"email":"ios@example.test","role":"admin"}"#.utf8)
            )
        }

        let client = AptevaAPIClient(
            baseURL: URL(string: "https://example.test")!,
            bearerToken: "sk-device-test",
            protocolClasses: [MockURLProtocol.self]
        )
        let user = try await client.currentUser()
        XCTAssertEqual(user.userID, 7)
        XCTAssertEqual(user.email, "ios@example.test")
    }

    func testMobileFavouriteUsesAnIndependentRevisionProtectedSurface() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/ui-layout/projects/project-1/surfaces/navigation.mobile-favourite")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-device-test")
            if request.httpMethod == "PATCH" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-Match"), "\"7\"")
                // URLSession may move the encoded body into a stream.
                XCTAssertNotNil(request.httpBody ?? request.httpBodyStream.map { _ in Data() })
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"value":["storage"],"revision":8}"#.utf8))
        }
        let client = AptevaAPIClient(baseURL: URL(string: "https://example.test")!, bearerToken: "sk-device-test", protocolClasses: [MockURLProtocol.self])
        let fetched = try await client.mobileFavouriteApp(projectID: "project-1")
        XCTAssertEqual(fetched.appName, "storage")
        let saved = try await client.updateMobileFavouriteApp(projectID: "project-1", appName: nil, revision: 7)
        XCTAssertEqual(saved.revision, 8)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(MobileFavouritePatch(value: [])), as: UTF8.self), #"{"value":[]}"#)
    }

    func testMobileFavouriteIsEmptyByDefault() throws {
        let preference = try JSONDecoder().decode(AptevaMobileFavouritePreference.self, from: Data(#"{"value":[],"revision":0}"#.utf8))
        XCTAssertNil(preference.appName)
    }

    func testAssetLoaderAuthenticatesOnlyTheSelectedServerOrigin() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.host == "example.test" {
                XCTAssertEqual(
                    request.value(forHTTPHeaderField: "Authorization"),
                    "Bearer sk-device-test"
                )
            } else {
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "image/*")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            return (response, Data([0x89, 0x50, 0x4e, 0x47]))
        }

        let client = AptevaAPIClient(
            baseURL: URL(string: "https://example.test")!,
            bearerToken: "sk-device-test",
            protocolClasses: [MockURLProtocol.self]
        )
        _ = try await client.assetData(reference: "/api/assets/app-icon.png")
        _ = try await client.assetData(reference: "https://cdn.example.test/app-icon.png")
        do {
            _ = try await client.assetData(reference: "http://example.test/insecure.png")
            XCTFail("Expected an insecure asset URL to be rejected")
        } catch let error as AptevaAPIError {
            guard case .invalidServerURL = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnreadSummaryIsScopedToRealProjectConversations() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            if request.url?.path.hasSuffix("/unread-summary") == true {
                return (response, Data(#"""
                [
                    {"chat_id":"project-chat","instance_id":7,"instance_name":"Agent","title":"Project","latest_id":5,"latest_role":"agent","latest_preview":"Ready","latest_at":"2026-09-20T08:00:00Z","last_seen_id":4},
                    {"chat_id":"other-chat","instance_id":8,"instance_name":"Other","title":"Other","latest_id":9,"latest_role":"agent","latest_preview":"Outside project","latest_at":"2026-09-20T08:00:00Z","last_seen_id":1}
                ]
                """#.utf8))
            }
            XCTAssertEqual(
                URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "project_id" })?.value,
                "project-1"
            )
            return (response, Data(#"""
            [
                {"id":"project-chat","instance_id":7,"agent_ids":[7],"project_id":"project-1","kind":"direct","title":"Project","created_at":"2026-09-20T07:00:00Z","updated_at":"2026-09-20T08:00:00Z"}
            ]
            """#.utf8))
        }

        let client = AptevaAPIClient(
            baseURL: URL(string: "https://example.test")!,
            bearerToken: "sk-device-test",
            protocolClasses: [MockURLProtocol.self]
        )
        let rows = try await client.unreadConversations(projectID: "project-1")
        XCTAssertEqual(rows.map(\.chatID), ["project-chat"])
    }

    func testInstalledAppDoesNotInventMissingLifecycleState() {
        let data = Data(#"""
        {
            "install_id":1,"app_id":2,"name":"storage","display_name":"Storage",
            "version":"1.0.0","project_id":"project-1","source":"registry",
            "upgrade_policy":"manual","deprecated":false
        }
        """#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AptevaInstalledApp.self, from: data))
    }

    func testInstalledAppDefaultsOmittedDeprecatedFlagToFalse() throws {
        let data = Data(#"""
        {
            "install_id":1,"app_id":2,"name":"storage","display_name":"Storage",
            "version":"1.0.0","project_id":"project-1","status":"running",
            "source":"registry","upgrade_policy":"manual"
        }
        """#.utf8)

        let app = try JSONDecoder().decode(AptevaInstalledApp.self, from: data)
        XCTAssertFalse(app.deprecated)
    }

    func testMarketplaceAppDefaultsOmittedDeprecatedFlagToFalse() throws {
        let data = Data(#"""
        {
            "name":"storage","display_name":"Storage","version":"1.0.0",
            "official":true,"installed":true,"builtin":false
        }
        """#.utf8)

        let app = try JSONDecoder().decode(AptevaMarketplaceApp.self, from: data)
        XCTAssertFalse(app.deprecated)
    }

    #if canImport(UIKit)
    func testAssetImagePayloadRecognizesRawSVG() throws {
        let data = Data(#"""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
          <path d="M2 2h20v20H2z" fill="currentColor"/>
        </svg>
        """#.utf8)

        guard case let .svg(image) = AptevaAssetImagePayload(data: data) else {
            return XCTFail("Expected an SVG image payload")
        }
        XCTAssertEqual(image.size, CGSize(width: 64, height: 64))
        XCTAssertNotNil(image.pngData())
    }

    func testAssetImagePayloadRendersDifferentSVGsDifferently() throws {
        let square = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="2" y="2" width="20" height="20" fill="currentColor"/></svg>"#.utf8)
        let circle = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="6" fill="currentColor"/></svg>"#.utf8)

        guard case let .svg(squareImage) = AptevaAssetImagePayload(data: square),
              case let .svg(circleImage) = AptevaAssetImagePayload(data: circle) else {
            return XCTFail("Expected native SVG image payloads")
        }
        XCTAssertNotEqual(squareImage.pngData(), circleImage.pngData())
    }

    func testAssetImagePayloadRejectsNonImageData() {
        XCTAssertNil(AptevaAssetImagePayload(data: Data("not an image".utf8)))
    }
    #endif

    func testChatV1NativeSurfaceDecodesGenericMappings() throws {
        let data = Data(#"""
        {
          "schema":"apteva-native-surface/v1",
          "id":"conversations",
          "version":"1.0.0",
          "title":"Conversations",
          "icon":"message-circle",
          "context":{"scope":"project"},
          "state":{"conversation_id":{"type":"string","default":""}},
          "data_sources":{
            "conversations":{"request":{"method":"GET","path":"/chats"},"response":{"items":"$.chats","id":"$.id"}},
            "messages":{"request":{"method":"GET","path":"/messages","query":{"conversation_id":"$state.conversation_id"}},"response":{"items":"$.messages","next_cursor":"$.next_cursor"},"pagination":{"type":"cursor","request_key":"before","response_path":"$.next_cursor","page_size":50}}
          },
          "sections":[{
            "id":"chat","kind":"component","component":"chat/v1",
            "chat":{
              "conversations_source":"conversations","messages_source":"messages","selection_state":"conversation_id","send_action":"send-message",
              "conversation":{"id":"$.id","title":"$.title","unread":"$.unread"},
              "message":{"id":"$.id","conversation_id":"$.conversation_id","body":"$.content","role":"$.role"},
              "live":{"id":"$.call_id","text":"$.text","done":"$.done","progress":{"value":"$.response_progress","phase":"$.phase"},"activity":{"value":"$.tool_activity","id":"$.id","status":"$.status"}},
              "subscription":{"request":{"method":"GET","path":"/stream","query":{"conversation_id":"$state.conversation_id"}},"cursor_query":"since","events":{"message":{"operation":"upsert","source":"messages","value":"$.message","id":"$.message.id"}}}
            }
          }],
          "actions":{"send-message":{"type":"request","label":"Send","request":{"method":"POST","path":"/messages","body":{"content":"$input.text"}},"result":"$.message"}}
        }
        """#.utf8)

        let surface = try JSONDecoder().decode(DeclaredNativeSurface.self, from: data)
        let chat = try XCTUnwrap(surface.sections.first?.chat)
        XCTAssertEqual(surface.sections.first?.component, "chat/v1")
        XCTAssertEqual(chat.messagesSource, "messages")
        XCTAssertEqual(chat.live?.text, "$.text")
        XCTAssertEqual(chat.live?.progress?.phase, "$.phase")
        XCTAssertEqual(chat.live?.activity?.status, "$.status")
        XCTAssertEqual(surface.dataSources["messages"]?.pagination?.type, "cursor")
        XCTAssertEqual(chat.subscription?.events["message"]?.operation, "upsert")
    }

    #if canImport(UIKit)
    func testResourceOptionsMapARootArrayWithoutASelectedValue() throws {
        let surfaceData = Data(#"""
        {
          "schema":"apteva-native-surface/v1",
          "id":"conversations",
          "version":"1.0.0",
          "title":"Conversations",
          "icon":"message-circle",
          "context":{"scope":"project"},
          "data_sources":{
            "agents":{
              "request":{"method":"GET","path":"/agents"},
              "response":{"items":"$","id":"$.id"}
            }
          },
          "sections":[],
          "resources":{
            "agent":{
              "type":"list",
              "label":"Agent",
              "source":"agents",
              "mapping":{"id":"$.id","label":"$.name"}
            }
          }
        }
        """#.utf8)
        let responseData = Data(#"""
        [
          {"id":1105,"name":"My Test Agent First","status":"stopped","attached":true},
          {"id":1118,"name":"Coding Agent","status":"stopped","attached":true}
        ]
        """#.utf8)

        let surface = try JSONDecoder().decode(DeclaredNativeSurface.self, from: surfaceData)
        let response = try JSONDecoder().decode(NativeJSONValue.self, from: responseData)
        let source = try XCTUnwrap(surface.dataSources["agents"])
        let resource = try XCTUnwrap(surface.resources["agent"])

        XCTAssertEqual(
            nativeSurfaceResourceOptions(response: response, source: source, mapping: resource.mapping),
            [
                ResolvedSurfaceOption(label: "My Test Agent First", value: .number(1105)),
                ResolvedSurfaceOption(label: "Coding Agent", value: .number(1118))
            ]
        )
    }

    func testChatHistorySnapshotPreservesMessagesThatArriveOverSSE() {
        let snapshot = [
            nativeChatMessage(id: 1, content: "First"),
            nativeChatMessage(id: 2, content: "Snapshot value")
        ]
        let live = [
            nativeChatMessage(id: 2, content: "Live value"),
            nativeChatMessage(id: 3, content: "Arrived during load")
        ]

        let merged = nativeChatMergingSnapshot(
            snapshot,
            preserving: live,
            idSelector: "$.id"
        )

        XCTAssertEqual(merged.compactMap(nativeChatID), [1, 2, 3])
        XCTAssertEqual(merged.compactMap(nativeChatContent), [
            "First", "Live value", "Arrived during load"
        ])
    }

    func testChatEventInsertionsDeduplicateByMappedID() {
        var messages = [nativeChatMessage(id: 2, content: "Original")]
        messages = nativeChatInserting(
            nativeChatMessage(id: 2, content: "Updated"),
            into: messages,
            idSelector: "$.id"
        )
        messages = nativeChatInserting(
            nativeChatMessage(id: 1, content: "Older"),
            into: messages,
            idSelector: "$.id",
            placement: .prepend
        )
        messages = nativeChatInserting(
            nativeChatMessage(id: 2, content: "Final"),
            into: messages,
            idSelector: "$.id",
            placement: .prepend
        )

        XCTAssertEqual(messages.compactMap(nativeChatID), [1, 2])
        XCTAssertEqual(messages.compactMap(nativeChatContent), ["Older", "Final"])
    }

    func testChatLiveTextFramesUpdateOneStableResponse() throws {
        let createdAt = Date(timeIntervalSince1970: 100)
        var responses: [String: NativeChatLiveResponse] = [:]

        responses = nativeChatApplyingLiveResponseFrame(
            to: responses,
            key: "7:thread:call:run",
            callID: "call",
            agentID: "7",
            text: "Hel",
            phase: "",
            done: false,
            now: createdAt
        )
        responses = nativeChatApplyingLiveResponseFrame(
            to: responses,
            key: "7:thread:call:run",
            callID: "call",
            agentID: "7",
            text: "Hello from the agent",
            phase: "",
            done: false,
            now: createdAt.addingTimeInterval(1)
        )

        XCTAssertEqual(responses.count, 1)
        let response = try XCTUnwrap(responses["7:thread:call:run"])
        XCTAssertEqual(response.id, "7:thread:call:run")
        XCTAssertEqual(response.text, "Hello from the agent")
        XCTAssertEqual(response.createdAt, createdAt)
        XCTAssertFalse(response.isComplete)
    }

    func testChatLiveDoneRetainsTextUntilDurableMessageArrives() throws {
        let key = "7:thread:call:run"
        let createdAt = Date(timeIntervalSince1970: 100)
        var responses = nativeChatApplyingLiveResponseFrame(
            to: [:],
            key: key,
            callID: "call",
            agentID: "7",
            text: "Complete response",
            phase: "",
            done: false,
            now: createdAt
        )

        responses = nativeChatApplyingLiveResponseFrame(
            to: responses,
            key: key,
            callID: "call",
            agentID: "7",
            text: "",
            phase: "",
            done: true
        )

        let response = try XCTUnwrap(responses[key])
        XCTAssertEqual(response.text, "Complete response")
        XCTAssertEqual(response.createdAt, createdAt)
        XCTAssertTrue(response.isComplete)
    }
    #endif

    func testNativeAppURLKeepsRoutesAppRelativeAndInjectsProject() throws {
        let client = AptevaAPIClient(
            baseURL: URL(string: "https://example.test")!,
            bearerToken: "sk-device-test",
            protocolClasses: [MockURLProtocol.self]
        )
        let url = try XCTUnwrap(client.nativeAppURL(
            appName: "conversations",
            projectID: "project-1",
            path: "/stream",
            query: ["conversation_id": "chat-1"]
        ))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/api/apps/conversations/stream")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "conversation_id" })?.value, "chat-1")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "project_id" })?.value, "project-1")
        XCTAssertNil(client.nativeAppURL(
            appName: "conversations",
            projectID: "project-1",
            path: "https://evil.example/stream"
        ))
    }

    func testConfirmedUnauthorizedIsClassifiedSeparately() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("unauthorized".utf8))
        }

        let client = AptevaAPIClient(
            baseURL: URL(string: "https://example.test")!,
            bearerToken: "sk-revoked",
            protocolClasses: [MockURLProtocol.self]
        )
        do {
            _ = try await client.currentUser()
            XCTFail("Expected an authentication error")
        } catch let error as AptevaAPIError {
            XCTAssertTrue(error.isUnauthorized)
            XCTAssertFalse(error.isConnectionFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testSSETransportAuthenticatesAndParsesNamedEvents() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer sk-stream-test"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Accept"),
                "text/event-stream"
            )
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Accept-Encoding"),
                "identity"
            )
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            let payload = """
            event: stream
            id: frame-1
            data: {"type":"stream","chat_id":"conv-1","call_id":"call-1","text":"Hello","done":false}
            """
            return (response, Data(payload.utf8))
        }

        let client = AptevaAPIClient(
            baseURL: URL(string: "https://example.test")!,
            bearerToken: "sk-stream-test",
            protocolClasses: [MockURLProtocol.self]
        )
        var events: [AptevaSSEEvent] = []
        for try await event in client.eventStream(
            "apps/channel-chat/stream?chat_id=conv-1&since=0"
        ) {
            events.append(event)
        }

        XCTAssertEqual(events.count, 2)
        guard events.count == 2 else {
            let summary = events.map {
                "\($0.name ?? "message"):\(String(decoding: $0.data, as: UTF8.self))"
            }.joined(separator: " | ")
            XCTFail(
                "Expected open and named stream events; "
                    + "got \(events.count): \(summary)"
            )
            return
        }
        XCTAssertEqual(events[0].name, AptevaSSETransport.openEventName)
        XCTAssertEqual(events[1].name, "stream")
        XCTAssertEqual(events[1].id, "frame-1")
    }

    func testChatMessagePreservesLifecyclePhase() throws {
        let data = Data(
            #"""
            {
              "id": 42,
              "chat_id": "conv-1",
              "role": "agent",
              "content": "I’ll check that now.",
              "status": "final",
              "created_at": "2026-07-30T10:00:00Z",
              "components": [],
              "attachments": [],
              "metadata": {"phase": "acknowledgement"}
            }
            """#.utf8
        )
        let message = try JSONDecoder().decode(AptevaConversationMessage.self, from: data)
        XCTAssertEqual(message.phase, "acknowledgement")
    }

}

private func nativeChatMessage(id: Int, content: String) -> NativeJSONValue {
    .object([
        "id": .number(Double(id)),
        "content": .string(content)
    ])
}

private func nativeChatID(_ message: NativeJSONValue) -> Int? {
    Int(message.value(at: "$.id")?.scalarString ?? "")
}

private func nativeChatContent(_ message: NativeJSONValue) -> String? {
    message.value(at: "$.content")?.scalarString
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            XCTFail("Missing URL protocol handler")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
