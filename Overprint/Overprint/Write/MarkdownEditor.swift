import SwiftUI
import AppKit

/// A plain-text Markdown editor backed by NSTextView, set in JetBrains Mono. Automatic
/// substitutions (smart quotes and dashes) are disabled so the source stays clean.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    var onEdit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .white

        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.allowsUndo = true
        textView.backgroundColor = .white
        textView.textColor = NSColor(Color(hex: 0x2A2A2E))
        textView.font = Self.editorFont
        textView.textContainerInset = NSSize(width: 20, height: 24)
        textView.defaultParagraphStyle = Self.paragraphStyle
        textView.typingAttributes = [
            .font: Self.editorFont,
            .foregroundColor: NSColor(Color(hex: 0x2A2A2E)),
            .paragraphStyle: Self.paragraphStyle,
        ]
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    static var editorFont: NSFont {
        NSFont(name: Fonts.familyName, size: 13.5)
            ?? NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    }

    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.35
        return style
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onEdit()
        }
    }
}
