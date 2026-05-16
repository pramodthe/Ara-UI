import AppKit
import SwiftUI

final class FloatingIconPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(contentView: NSView) {
        super.init(contentRect: NSRect(x: 200, y: 200, width: 80, height: 48),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        setFrame(NSRect(x: 200, y: 200, width: 80, height: 48), display: false)
        self.contentView = contentView
    }
}

final class FloatingIconWindowController: NSWindowController {
    private var initialOrigin: NSPoint?

    init(viewModel: ChatViewModel,
         onClick: @escaping () -> Void,
         onDragChanged: @escaping (CGSize) -> Void,
         onDragEnded: @escaping () -> Void) {
        let root = SparklesIconView(
            onClick: onClick,
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        ).environmentObject(viewModel)
        let hosting = NSHostingView(rootView: root)
        let panel = FloatingIconPanel(contentView: hosting)
        super.init(window: panel)
        shouldCascadeWindows = false
        window?.isReleasedWhenClosed = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var panel: FloatingIconPanel? { window as? FloatingIconPanel }

    func beginDragIfNeeded() {
        if initialOrigin == nil, let w = window { initialOrigin = w.frame.origin }
    }

    func moveBy(translation: CGSize) {
        guard let w = window else { return }
        if initialOrigin == nil { initialOrigin = w.frame.origin }
        guard let start = initialOrigin else { return }
        let newOrigin = NSPoint(x: start.x + translation.width, y: start.y - translation.height)
        w.setFrameOrigin(clamped(origin: newOrigin, windowSize: w.frame.size))
    }

    func endDrag() {
        initialOrigin = nil
    }

    private func clamped(origin: NSPoint, windowSize: NSSize) -> NSPoint {
        guard let screen = window?.screen ?? NSScreen.main else { return origin }
        let frame = screen.visibleFrame
        let minX = frame.minX
        let maxX = frame.maxX - windowSize.width
        let minY = frame.minY
        let maxY = frame.maxY - windowSize.height
        let x = max(minX, min(maxX, origin.x))
        let y = max(minY, min(maxY, origin.y))
        return NSPoint(x: x, y: y)
    }
}


