//
//  MarkdownText.swift
//  nova
//
//  Renders basic Markdown safely in SwiftUI using AttributedString(markdown:).
//

import SwiftUI
import Foundation

struct MarkdownText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            // Use Text initialiser for AttributedString to preserve styles like bold/italic/code
            Text(attributed)
                .textSelection(.enabled)
        } else {
            // Fallback to plain text if parsing fails
            Text(markdown)
                .textSelection(.enabled)
        }
    }
}

// Convenience wrapper for block-level Markdown (headings, lists, code blocks)
// SwiftUI Text supports block markdown parsing directly via init(verbatim:) + markdown rendering on macOS 12+.
// For richer blocks like code blocks with monospaced font, we lightly post-style using detection.
struct MarkdownBlockText: View {
    let markdown: String

    var body: some View {
        // Treat single newlines as hard line breaks outside fenced code blocks
        let processed = MarkdownBlockText.applyHardBreaksOutsideCodeFences(markdown)
        if let attributed = try? AttributedString(markdown: processed) {
            Text(attributed)
                .textSelection(.enabled)
        } else {
            Text(processed)
                .textSelection(.enabled)
        }
    }
}

private extension MarkdownBlockText {
    // Convert single \n into Markdown hard-breaks (two spaces + \n) outside of fenced code blocks.
    // Leave double newlines (paragraph breaks) intact, and don't touch text inside ``` fences.
    static func applyHardBreaksOutsideCodeFences(_ input: String) -> String {
        // Normalize newlines first
        let normalized = input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Split by triple backtick fences. Odd indices are inside a fence.
        let parts = normalized.components(separatedBy: "```")
        var rebuilt = String()
        for (index, part) in parts.enumerated() {
            if index > 0 { rebuilt += "```" }
            if index % 2 == 1 {
                // Inside code fence: keep as-is
                rebuilt += part
            } else {
                // Outside fence: replace single newlines with hard-breaks
                rebuilt += replaceSingleNewlinesWithHardBreaks(part)
            }
        }
        return rebuilt
    }

    static func replaceSingleNewlinesWithHardBreaks(_ text: String) -> String {
        // Protect double newlines using a placeholder, then convert single newlines to hard-breaks
        let placeholder = "\u{000B}" // vertical tab as unlikely token
        let protected = text.replacingOccurrences(of: "\n\n", with: placeholder)
        let singlesAsHardBreaks = protected.replacingOccurrences(of: "\n", with: "  \n")
        let restored = singlesAsHardBreaks.replacingOccurrences(of: placeholder, with: "\n\n")
        return restored
    }
}


