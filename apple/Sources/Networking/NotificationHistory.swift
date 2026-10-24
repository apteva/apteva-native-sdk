import Foundation

public struct NativeChatHistoryPage: Sendable {
    public let messages: [NativeJSONValue]
    public let nextCursor: String?
    public init(messages: [NativeJSONValue], nextCursor: String?) {
        self.messages = messages
        self.nextCursor = nextCursor
    }
}

/// Resolve a notification into contiguous history, with bounded, cycle-safe
/// pagination. A deleted/missing target is an error, never a successful open.
@MainActor
public func nativeChatNotificationHistory(
    initial: NativeChatHistoryPage,
    targetMessageID: String?,
    idSelector: String,
    loadOlder: (String) async throws -> NativeChatHistoryPage
) async throws -> NativeChatHistoryPage {
    guard let targetMessageID else { return initial }
    var page = initial
    var visited = Set<String>()
    while !page.messages.contains(where: { nativeChatMessageID($0, selector: idSelector) == targetMessageID }) {
        try Task.checkCancellation()
        guard let cursor = page.nextCursor, visited.insert(cursor).inserted, visited.count <= 200 else {
            throw AptevaAPIError.connection("The notification’s message is no longer available in this conversation.")
        }
        let older = try await loadOlder(cursor)
        page = NativeChatHistoryPage(
            messages: nativeChatMergingSnapshot(older.messages, preserving: page.messages, idSelector: idSelector),
            nextCursor: older.nextCursor
        )
    }
    return page
}
