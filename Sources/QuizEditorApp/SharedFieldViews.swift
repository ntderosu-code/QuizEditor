import SwiftUI
import UniformTypeIdentifiers
import AppKit
import WebKit
import QuizEditorCore
#if canImport(FoundationModels)
import FoundationModels
#endif

struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content
                .accessibilityLabel(title)
        }
    }
}

struct LabeledTextEditor: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat
    /// Optional grey prompt shown only while the field is empty. It is not part of
    /// the text, so it can never be submitted or imported by mistake.
    var placeholder: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled(false)
                    .padding(8)
                    .frame(minHeight: minHeight)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(.rect(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .accessibilityLabel(title)

                // Drawn on top so it shows over the editor's opaque background;
                // hit testing is disabled so clicks fall through to the editor.
                if let placeholder, text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// A hover highlight for rows that are clickable but not drawn as buttons.
/// `.buttonStyle(.plain)` removes macOS's built-in hover feedback, which leaves
/// a clickable row looking inert until you click it. The tint is drawn from
/// `Color.primary`, so it adapts to light and dark automatically, and it is
/// never the only signal — every row it is applied to also carries its own
/// label, selection state, and accessibility traits.
struct HoverHighlight: ViewModifier {
    var cornerRadius: CGFloat = 6
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            )
            .onHover { isHovered = $0 }
    }
}

extension View {
    func hoverHighlight(cornerRadius: CGFloat = 6) -> some View {
        modifier(HoverHighlight(cornerRadius: cornerRadius))
    }
}
