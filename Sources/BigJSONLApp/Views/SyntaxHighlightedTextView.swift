import AppKit
import BigJSONLCore
import SwiftUI

/// AppKit-backed selectable text for efficiently rendering large highlighted JSON.
struct SyntaxHighlightedTextView: NSViewRepresentable {
    let content: JSONDisplayContent
    let contentID: UInt64

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.renderedContentID != contentID,
              let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.textStorage?.setAttributedString(makeAttributedString())
        context.coordinator.renderedContentID = contentID
    }

    private func makeAttributedString() -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: content.text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        let utf8Count = content.text.utf8.count
        if utf8Count == content.text.utf16.count {
            applyASCIIColors(to: result, utf8Count: utf8Count)
            return result
        }

        let bytes = Array(content.text.utf8)
        var bytePosition = 0
        var utf16Position = 0

        for token in content.tokens {
            let start = min(Int(token.range.lowerBound), bytes.count)
            let end = min(Int(token.range.upperBound), bytes.count)
            guard start >= bytePosition, end >= start else { continue }

            utf16Position += utf16Length(of: bytes[bytePosition..<start])
            let tokenLength = utf16Length(of: bytes[start..<end])
            if tokenLength > 0 {
                result.addAttribute(
                    .foregroundColor,
                    value: color(for: token.type),
                    range: NSRange(location: utf16Position, length: tokenLength)
                )
            }
            utf16Position += tokenLength
            bytePosition = end
        }

        return result
    }

    private func applyASCIIColors(
        to result: NSMutableAttributedString,
        utf8Count: Int
    ) {
        for token in content.tokens {
            let start = min(Int(token.range.lowerBound), utf8Count)
            let end = min(Int(token.range.upperBound), utf8Count)
            guard end > start else { continue }

            result.addAttribute(
                .foregroundColor,
                value: color(for: token.type),
                range: NSRange(location: start, length: end - start)
            )
        }
    }

    private func utf16Length(of bytes: ArraySlice<UInt8>) -> Int {
        String(decoding: bytes, as: UTF8.self).utf16.count
    }

    private func color(for type: TokenType) -> NSColor {
        switch type {
        case .punctuation: .secondaryLabelColor
        case .key: .systemCyan
        case .stringValue: .systemOrange
        case .number: .systemPurple
        case .bool, .null: .systemGreen
        case .invalid: .systemRed
        }
    }

    final class Coordinator {
        var renderedContentID: UInt64?
    }
}
