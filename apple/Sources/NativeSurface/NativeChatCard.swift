import Foundation

/// Standard Conversations card semantics, independent of a host's visual style.
public struct NativeChatCard: Identifiable, Sendable {
    public enum Kind: String, Sendable { case alert, approval, report, interaction, unsupported }
    public let id: String
    public let componentID: String
    public let app: String
    public let name: String
    public let kind: Kind
    public let props: [String: NativeJSONValue]
    public let interaction: [String: NativeJSONValue]?
    public let supported: Bool

    public init(_ value: NativeJSONValue, index: Int = 0) {
        let object = value.objectValue ?? [:]
        componentID = object["id"]?.scalarString ?? ""
        app = object["app"]?.scalarString ?? ""
        name = object["name"]?.scalarString ?? ""
        id = "\(index):\(componentID):\(app)/\(name)"
        props = object["props"]?.objectValue ?? [:]
        interaction = object["interaction"]?.objectValue
        supported = object["version"] == nil || object["version"] == .number(1)
        if supported && ["conversations", "channel-chat"].contains(app) {
            switch name {
            case "alert-card": kind = .alert
            case "approval-card": kind = .approval
            case "report-card": kind = .report
            default: kind = interaction == nil ? .unsupported : .interaction
            }
        } else { kind = supported && interaction != nil ? .interaction : .unsupported }
    }

    public func text(_ key: String) -> String { props[key]?.scalarString ?? "" }
    public var title: String { text("title") }
    public var detail: String {
        switch kind {
        case .alert: text("text")
        case .report: text("summary")
        default: text("body")
        }
    }
    public var severity: String { text("severity").isEmpty ? "info" : text("severity") }
    public var label: String {
        switch kind {
        case .alert: severity == "error" ? "Error" : ["warn", "warning"].contains(severity) ? "Warning" : "Info"
        case .approval: "Approval requested"
        case .report: "Report"
        case .interaction: "Question"
        case .unsupported: "Additional content"
        }
    }
    public var status: String {
        if kind == .approval { return text("status").isEmpty ? "pending" : text("status") }
        return interaction?["status"]?.scalarString ?? "pending"
    }
    public func isPending(now: Date = Date()) -> Bool {
        guard supported, status == "pending" else { return false }
        if let expires = interaction?["expires_at"]?.scalarString {
            guard let date = parseAptevaDate(expires), date > now else { return false }
        }
        return kind == .approval || kind == .interaction
    }
    public var actions: [NativeChatCardAction] {
        let values = kind == .approval ? props["actions"] : interaction?["actions"]
        return (values?.arrayValue ?? []).compactMap(NativeChatCardAction.init)
    }
    public var fields: [NativeChatCardField] {
        (interaction?["fields"]?.arrayValue ?? []).compactMap(NativeChatCardField.init)
    }
    public var sections: [NativeJSONValue] { props["sections"]?.arrayValue ?? [] }
    public var savedValues: [String: NativeJSONValue] { interaction?["values"]?.objectValue ?? [:] }
    public var decisionLabel: String {
        let actionID = kind == .approval ? status : interaction?["action_id"]?.scalarString ?? ""
        if let action = actions.first(where: { $0.id == actionID }) { return "Decision: \(action.label)" }
        switch status {
        case "approve", "approved": return "Approved"
        case "deny", "denied": return "Declined"
        case "answered": return "Answered"
        case "cancelled", "canceled": return "Cancelled"
        case "pending": return "Expired"
        default: return status.capitalized
        }
    }

    /// Preserve legacy approval verdicts: those deliberately omit component_id
    /// and send note, even when newer approvals also carry an interaction.
    public func actionBody(messageID: NativeJSONValue, action: NativeChatCardAction,
                           values: [String: NativeJSONValue], note: String, now: Date = Date()) throws -> [String: NativeJSONValue] {
        guard isPending(now: now), actions.contains(where: { $0.id == action.id }) else {
            throw NativeChatCardError.unavailable
        }
        if kind == .approval {
            return ["message_id": messageID, "action_id": .string(action.id), "note": .string(note)]
        }
        guard !componentID.isEmpty else { throw NativeChatCardError.unavailable }
        if !action.cancel {
            for field in fields where !field.isValid(values[field.id]) {
                throw NativeChatCardError.invalidField(field.label)
            }
        }
        return ["message_id": messageID, "component_id": .string(componentID),
                "action_id": .string(action.id), "values": .object(values)]
    }
}

public enum NativeChatCardError: LocalizedError {
    case unavailable, invalidField(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable: "This request has changed or is no longer available."
        case .invalidField(let label): "Check \(label) before continuing."
        }
    }
}

public struct NativeChatCardAction: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let style: String
    public let cancel: Bool
    public init?(_ value: NativeJSONValue) {
        guard let object = value.objectValue, let id = object["id"]?.scalarString, !id.isEmpty else { return nil }
        self.id = id
        label = object["label"]?.scalarString ?? id
        style = object["style"]?.scalarString ?? "secondary"
        cancel = object["cancel"]?.boolValue ?? false
    }
}

public struct NativeChatCardField: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let type: String
    public let required: Bool
    public let allowCustom: Bool
    public let options: [NativeChatCardAction]
    public init?(_ value: NativeJSONValue) {
        guard let object = value.objectValue, let id = object["id"]?.scalarString, !id.isEmpty else { return nil }
        self.id = id
        label = object["label"]?.scalarString ?? id
        type = object["type"]?.scalarString ?? "text"
        required = object["required"]?.boolValue ?? false
        allowCustom = object["allow_custom"]?.boolValue ?? false
        options = (object["options"]?.arrayValue ?? []).compactMap(NativeChatCardAction.init)
    }
    public func isValid(_ value: NativeJSONValue?) -> Bool {
        let text = value?.scalarString.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty { return !required }
        if type == "multichoice" {
            guard let values = value?.arrayValue else { return false }
            return values.allSatisfy { value in options.contains { $0.id == value.scalarString } }
        }
        if type == "choice" && !allowCustom { return options.contains { $0.id == text } }
        return ["text", "textarea", "choice"].contains(type) && text.count <= 8000
    }
    public func display(_ value: NativeJSONValue) -> String {
        if let array = value.arrayValue { return array.map { display($0) }.joined(separator: ", ") }
        return options.first { $0.id == value.scalarString }?.label ?? value.scalarString
    }
}

public func nativeChatCards(in item: NativeJSONValue, selector: String = "$.components") -> [NativeChatCard] {
    (item.value(at: selector)?.arrayValue ?? []).enumerated().compactMap { index, value in
        guard value.objectValue != nil else { return nil }
        if value.value(at: "$.app")?.scalarString == "conversations",
           ["reply-suggestion", "reply-suggestions"].contains(value.value(at: "$.name")?.scalarString ?? "") { return nil }
        return NativeChatCard(value, index: index)
    }
}

public func nativeChatBody(_ body: String, beside cards: [NativeChatCard]) -> String {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    // Hide only exact duplicates; commentary alongside a card must survive.
    let duplicated = cards.contains { card in
        card.kind != .unsupported && ([card.title, card.detail, [card.title, card.detail].filter { !$0.isEmpty }.joined(separator: "\n"),
            card.kind == .approval ? "Approval requested: " + card.title : "",
            card.kind == .report ? "Report: " + card.title : ""]
            .contains(trimmed))
    }
    return duplicated ? "" : trimmed
}
