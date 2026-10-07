#if canImport(UIKit)
import SwiftUI

// The native-surface renderer is packaged independently from the application.
// Keep its small set of presentation tokens here so it does not depend on app UI.
enum AptevaPalette {
    static let background = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let card = Color(red: 20 / 255, green: 20 / 255, blue: 20 / 255)
    static let raised = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)
    static let border = Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
    static let text = Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255)
    static let muted = Color(red: 170 / 255, green: 170 / 255, blue: 170 / 255)
    static let dim = Color(red: 136 / 255, green: 136 / 255, blue: 136 / 255)
    static let accent = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    static let error = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
}

extension Font {
    static func apteva(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}

struct AptevaLoadingView: View {
    let title: String
    let detail: String?
    let minimumHeight: CGFloat
    let compact: Bool

    init(_ title: String, detail: String? = nil, minimumHeight: CGFloat = 240, compact: Bool = false) {
        self.title = title
        self.detail = detail
        self.minimumHeight = minimumHeight
        self.compact = compact
    }

    var body: some View {
        VStack(spacing: compact ? 10 : 14) {
            ZStack {
                Circle().fill(AptevaPalette.accent.opacity(0.1))
                Circle().stroke(AptevaPalette.accent.opacity(0.22), lineWidth: 1)
                ProgressView()
                    .tint(AptevaPalette.accent)
                    .controlSize(compact ? .small : .regular)
            }
            .frame(width: compact ? 36 : 48, height: compact ? 36 : 48)

            VStack(spacing: 5) {
                Text(title)
                    .font(.apteva(compact ? .caption : .subheadline, weight: .semibold))
                    .foregroundStyle(AptevaPalette.text)
                    .multilineTextAlignment(.center)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.apteva(.caption2))
                        .foregroundStyle(AptevaPalette.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
        .padding(compact ? 12 : 24)
        .frame(maxWidth: .infinity, minHeight: minimumHeight, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { "\(title). \($0)" } ?? title)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.apteva(.caption, weight: .bold))
            .foregroundStyle(AptevaPalette.accent)
    }
}

struct GlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AptevaPalette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
#endif
