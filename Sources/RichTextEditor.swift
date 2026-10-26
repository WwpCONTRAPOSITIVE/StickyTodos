import AppKit
import SwiftUI

struct BoldSpan: Codable, Equatable {
    var location: Int
    var length: Int
}

enum RichTextFormatting {
    static let boldKey = NSAttributedString.Key("StickyTodosBold")
    static let fontSize: CGFloat = 12

    static func normalizedSpans(_ spans: [BoldSpan], in text: String) -> [BoldSpan] {
        let total = (text as NSString).length
        let valid = spans.filter { span in
            span.location >= 0 && span.length > 0 && span.location <= total
                && span.length <= total - span.location
                && Range(NSRange(location: span.location, length: span.length), in: text) != nil
        }.sorted { $0.location < $1.location }

        var merged: [BoldSpan] = []
        for span in valid {
            if let last = merged.last,
               span.location <= last.location + last.length {
                merged[merged.count - 1].length = max(
                    last.location + last.length,
                    span.location + span.length
                ) - last.location
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    static func attributed(title: String, spans: [BoldSpan]) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )
        for span in normalizedSpans(spans, in: title) {
            let range = NSRange(location: span.location, length: span.length)
            result.addAttributes([
                boldKey: true,
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
            ], range: range)
        }
        return result
    }

    static func spans(from attributed: NSAttributedString) -> [BoldSpan] {
        guard attributed.length > 0 else { return [] }
        var spans: [BoldSpan] = []
        attributed.enumerateAttribute(
            boldKey,
            in: NSRange(location: 0, length: attributed.length),
            options: []
        ) { value, range, _ in
            if (value as? Bool) == true {
                spans.append(BoldSpan(location: range.location, length: range.length))
            }
        }
        return normalizedSpans(spans, in: attributed.string)
    }

    static func displayText(_ title: String, spans: [BoldSpan]) -> Text {
        let source = title as NSString
        var result = Text("")
        var cursor = 0
        for span in normalizedSpans(spans, in: title) {
            let before = source.substring(with: NSRange(
                location: cursor, length: span.location - cursor
            ))
            let bold = source.substring(with: NSRange(
                location: span.location, length: span.length
            ))
            result = result + Text(before) + Text(bold).bold()
            cursor = span.location + span.length
        }
        let tail = source.substring(from: cursor)
        return result + Text(tail)
    }
}

final class RichTextEditorHandle {
    weak var textView: NSTextView?
    var didChange: ((NSAttributedString) -> Void)?

    func toggleBold() {
        guard let textView,
              let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        guard selection.length > 0,
              selection.location + selection.length <= storage.length else { return }

        var allBold = true
        storage.enumerateAttribute(
            RichTextFormatting.boldKey,
            in: selection,
            options: []
        ) { value, _, _ in
            if (value as? Bool) != true { allBold = false }
        }

        storage.beginEditing()
        if allBold {
            storage.removeAttribute(RichTextFormatting.boldKey, range: selection)
            storage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(
                    ofSize: RichTextFormatting.fontSize, weight: .regular
                ),
                range: selection
            )
        } else {
            storage.addAttributes([
                RichTextFormatting.boldKey: true,
                .font: NSFont.monospacedSystemFont(
                    ofSize: RichTextFormatting.fontSize, weight: .bold
                )
            ], range: selection)
        }
        storage.endEditing()
        didChange?(NSAttributedString(attributedString: storage))
        textView.window?.makeFirstResponder(textView)
    }
}

private final class ShortcutTextView: NSTextView {
    var onBoldShortcut: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([
            .command, .shift, .option, .control
        ])
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "b" {
            onBoldShortcut?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var spans: [BoldSpan]
    let handle: RichTextEditorHandle

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = ShortcutTextView(frame: NSRect(
            x: 0, y: 0, width: 300, height: 110
        ))
        textView.isRichText = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textStorage?.setAttributedString(
            RichTextFormatting.attributed(title: text, spans: spans)
        )
        textView.delegate = context.coordinator
        textView.onBoldShortcut = { [weak handle] in handle?.toggleBold() }
        scrollView.documentView = textView
        handle.textView = textView
        setChangeHandler()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        setChangeHandler()
    }

    private func setChangeHandler() {
        let textBinding = _text
        let spansBinding = _spans
        handle.didChange = { attributed in
            textBinding.wrappedValue = attributed.string
            spansBinding.wrappedValue = RichTextFormatting.spans(from: attributed)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.spans = RichTextFormatting.spans(from: textView.attributedString())
        }
    }
}
