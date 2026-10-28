#if canImport(SwiftUI)
import SwiftUI

public struct NativeChatCardView: View {
    let card: NativeChatCard
    let canRespond: Bool
    let submit: (NativeChatCardAction, [String: NativeJSONValue], String) async throws -> Void
    @State private var note = ""
    @State private var values: [String: NativeJSONValue] = [:]
    @State private var customFields: Set<String> = []
    @State private var busy = false
    @State private var error: String?
    @State private var confirmation: NativeChatCardAction?

    public init(card: NativeChatCard, canRespond: Bool,
                submit: @escaping (NativeChatCardAction, [String: NativeJSONValue], String) async throws -> Void) {
        self.card = card
        self.canRespond = canRespond
        self.submit = submit
    }

    private var tone: Color {
        switch card.kind {
        case .alert: card.severity == "error" ? .red : ["warn", "warning"].contains(card.severity) ? .orange : .blue
        case .approval: .orange
        case .report: .blue
        default: AptevaPalette.accent
        }
    }
    private var symbol: String {
        switch card.kind {
        case .alert: card.severity == "error" ? "exclamationmark.octagon.fill" : ["warn", "warning"].contains(card.severity) ? "exclamationmark.triangle.fill" : "info.circle.fill"
        case .approval: "checkmark.seal"
        case .report: "doc.text"
        case .interaction: "questionmark.bubble"
        case .unsupported: "square.stack"
        }
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let pending = card.isPending(now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label(card.label, systemImage: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tone)
                    Spacer(minLength: 8)
                    if !card.text("period").isEmpty {
                        Text(card.text("period")).font(.caption).foregroundStyle(AptevaPalette.muted)
                    }
                    if busy { ProgressView().controlSize(.small) }
                }
                if !card.title.isEmpty { Text(card.title).font(.headline).textSelection(.enabled) }
                if !card.detail.isEmpty && card.detail != card.title { nativeText(card.detail) }
                if card.kind == .report {
                    ForEach(Array(card.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 6) {
                            let heading = section.value(at: "$.title")?.scalarString ?? section.value(at: "$.heading")?.scalarString ?? ""
                            if !heading.isEmpty { Text(heading).font(.subheadline.bold()) }
                            let text = section.value(at: "$.body")?.scalarString ?? section.value(at: "$.content")?.scalarString ?? section.value(at: "$.text")?.scalarString ?? section.scalarString
                            if !text.isEmpty { nativeText(text) }
                        }
                        .padding(.top, 4)
                    }
                }
                if card.kind == .approval || card.kind == .interaction {
                    Divider().overlay(AptevaPalette.border)
                    if pending && canRespond {
                        if card.kind == .approval {
                            TextField("Add a note (optional)", text: $note, axis: .vertical)
                                .textFieldStyle(.roundedBorder).lineLimit(1...4)
                                .accessibilityLabel("Approval note")
                        } else {
                            Text(card.interaction?["blocking"]?.boolValue == true ? "Waiting for your response" : "Optional response")
                                .font(.caption).foregroundStyle(AptevaPalette.muted)
                            ForEach(card.fields) { field in fieldInput(field) }
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { actionButtons }
                            VStack(alignment: .leading, spacing: 10) { actionButtons }
                        }
                        .disabled(busy)
                    } else if pending {
                        Text("Open this conversation in the dashboard to respond.")
                            .font(.subheadline).foregroundStyle(AptevaPalette.muted)
                    } else {
                        Label(card.decisionLabel, systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.medium))
                        if !card.text("note").isEmpty { nativeText(card.text("note")) }
                        ForEach(card.fields) { field in
                            if let value = card.savedValues[field.id] {
                                Text("\(field.label): \(field.display(value))").font(.subheadline).textSelection(.enabled)
                            }
                        }
                    }
                }
                if card.kind == .unsupported {
                    Text("Open this conversation in the dashboard to view this content.")
                        .font(.subheadline).foregroundStyle(AptevaPalette.muted)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red).accessibilityAddTraits(.updatesFrequently) }
            }
            .disabled(busy)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AptevaPalette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(tone.opacity(0.35), lineWidth: 1))
            .foregroundStyle(AptevaPalette.text)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("chat-card-\(card.name)-\(card.componentID)")
        }
        .confirmationDialog(confirmation?.label ?? "Confirm action", isPresented: Binding(
            get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
        ), titleVisibility: .visible) {
            if let action = confirmation {
                Button(action.label, role: .destructive) { Task { await act(action) } }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: { Text(card.title.isEmpty ? "This action cannot necessarily be undone." : card.title) }
    }

    private func nativeText(_ text: String) -> some View {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .font(.body).lineSpacing(3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var actionButtons: some View {
        ForEach(card.actions) { action in
            Button(role: action.style == "danger" ? .destructive : nil) {
                if action.style == "danger" { confirmation = action }
                else { Task { await act(action) } }
            } label: {
                Text(action.label).fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 30)
            }
            .buttonStyle(.bordered)
            .tint(action.style == "danger" ? .red : action.style == "primary" ? AptevaPalette.accent : AptevaPalette.muted)
            .accessibilityIdentifier("chat-card-action-\(action.id)")
        }
    }

    @ViewBuilder private func fieldInput(_ field: NativeChatCardField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label + (field.required ? " *" : "")).font(.subheadline.weight(.medium))
            if field.type == "multichoice" {
                ForEach(field.options) { option in
                    let selected = values[field.id]?.arrayValue ?? []
                    Toggle(option.label, isOn: Binding(get: { selected.contains(.string(option.id)) }, set: { checked in
                        values[field.id] = .array(checked ? selected + [.string(option.id)] : selected.filter { $0 != .string(option.id) })
                    })).toggleStyle(.switch)
                }
            } else if field.type == "choice" && !customFields.contains(field.id) {
                Picker(field.label, selection: stringBinding(field.id)) {
                    Text("Choose…").tag("")
                    ForEach(field.options) { option in Text(option.label).tag(option.id) }
                }.pickerStyle(.menu)
                if field.allowCustom {
                    Button("Write another answer") { customFields.insert(field.id); values[field.id] = .string("") }
                        .font(.caption)
                }
            } else if ["text", "textarea", "choice"].contains(field.type) {
                TextField(field.label, text: stringBinding(field.id), axis: .vertical)
                    .lineLimit(field.type == "textarea" ? 3...8 : 1...4).textFieldStyle(.roundedBorder)
                if field.type == "choice" && customFields.contains(field.id) {
                    Button("Choose from options") { customFields.remove(field.id); values[field.id] = .string("") }.font(.caption)
                }
            } else {
                Text("This answer type is available in the dashboard.").font(.caption).foregroundStyle(AptevaPalette.muted)
            }
        }
    }

    private func stringBinding(_ key: String) -> Binding<String> {
        Binding(get: { values[key]?.scalarString ?? "" }, set: { values[key] = .string(String($0.prefix(8000))) })
    }
    @MainActor private func act(_ action: NativeChatCardAction) async {
        guard !busy, card.isPending() else { return }
        busy = true; error = nil
        defer { busy = false; confirmation = nil }
        do { try await submit(action, values, note) }
        catch { self.error = error.localizedDescription }
    }
}
#endif
