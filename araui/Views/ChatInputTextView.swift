//
//  ChatInputTextView.swift
//  nova
//
//  NSTextView wrapper to support Enter-to-send and Shift+Enter for newline.
//

import SwiftUI
import AppKit

struct ChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool = true
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = SubmitTextView()
        textView.delegate = context.coordinator
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isRichText = false
        textView.isEditable = isEnabled
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.backgroundColor = .clear
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onReturnWithoutShift = { [weak coordinator = context.coordinator] in
            coordinator?.onSubmit()
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.startObserving()
        textView.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        // Keep editability in sync with SwiftUI state
        if textView.isEditable != isEnabled {
            textView.isEditable = isEnabled
        }
        if let container = textView.textContainer, let superview = textView.superview {
            container.containerSize = NSSize(width: superview.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        }
        // Ensure caret is visible when SwiftUI updates the text view layout
        context.coordinator.scrollCaretIntoView()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        @Binding var text: String
        let onSubmit: () -> Void
        private var isObserving: Bool = false

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self._text = text
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            text = tv.string
            scrollCaretIntoView()
        }

        func scrollCaretIntoView() {
            guard let tv = textView, let layoutManager = tv.layoutManager, let textContainer = tv.textContainer else { return }
            let selectedRange = tv.selectedRange()
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
            let caretRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let converted = tv.convert(caretRect, to: tv.enclosingScrollView?.contentView)
            tv.enclosingScrollView?.contentView.scrollToVisible(converted)
            tv.enclosingScrollView?.reflectScrolledClipView(tv.enclosingScrollView!.contentView)
        }

        // Observe app/window activation to restore focus to the input
        func startObserving() {
            guard isObserving == false else { return }
            isObserving = true
            NotificationCenter.default.addObserver(self, selector: #selector(handleAppBecameActive), name: NSApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleWindowBecameKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)
        }

        deinit {
            if isObserving {
                NotificationCenter.default.removeObserver(self)
            }
        }

        @objc private func handleAppBecameActive() {
            restoreFirstResponder()
        }

        @objc private func handleWindowBecameKey(_ note: Notification) {
            restoreFirstResponder()
        }

        private func restoreFirstResponder() {
            guard let tv = textView else { return }
            // Only attempt to focus if the window is key and the view is editable
            guard let window = tv.window, window.isKeyWindow, tv.isEditable else { return }
            if window.firstResponder !== tv {
                window.makeFirstResponder(tv)
                scrollCaretIntoView()
            }
        }
    }
}

final class SubmitTextView: NSTextView {
    var onReturnWithoutShift: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Return: 36, Enter (keypad): 76
        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.shift) {
                super.insertNewline(self)
                return
            } else {
                onReturnWithoutShift?()
                return
            }
        }
        super.keyDown(with: event)
    }
}


