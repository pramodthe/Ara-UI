import SwiftUI
import AppKit

@MainActor
final class ScreenGlowController {
    static let shared = ScreenGlowController()

    private var glowWindow: NSPanel?
    private var screenChangeObserver: NSObjectProtocol?

    private init() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateForScreenChanges()
        }
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func showGlow(on screen: NSScreen? = NSScreen.main, style: GlowStyle = .listening) {
        guard let screen else {
            hideGlow()
            return
        }

        if let existing = glowWindow {
            if existing.screen != screen {
                hideGlow()
                createGlowWindow(for: screen, style: style)
            } else {
                update(window: existing, for: screen, style: style)
                existing.orderFrontRegardless()
            }
        } else {
            createGlowWindow(for: screen, style: style)
        }
    }
    
    enum GlowStyle {
        case listening
        case processing
    }

    func hideGlow() {
        guard let window = glowWindow else { return }
        window.orderOut(nil)
        window.contentView = nil
        glowWindow = nil
    }

    var isGlowVisible: Bool {
        glowWindow != nil
    }

    func isGlowWindow(_ window: NSWindow) -> Bool {
        glowWindow === window
    }

    // MARK: - Private helpers

    private func createGlowWindow(for screen: NSScreen, style: GlowStyle) {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        configure(panel: panel, for: screen)

        let hostingView = NSHostingView(rootView: ScreenGlowView(style: style))
        hostingView.frame = panel.contentView?.bounds ?? panel.frame
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        glowWindow = panel
    }

    private func configure(panel: NSPanel, for screen: NSScreen) {
        panel.setFrame(screen.frame, display: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.isReleasedWhenClosed = false
    }

    private func update(window: NSPanel, for screen: NSScreen, style: GlowStyle) {
        configure(panel: window, for: screen)
        let hostingView = NSHostingView(rootView: ScreenGlowView(style: style))
        hostingView.frame = window.contentView?.bounds ?? window.frame
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = hostingView
    }

    private func updateForScreenChanges() {
        guard let window = glowWindow else { return }
        let targetScreen = window.screen ?? NSScreen.main
        showGlow(on: targetScreen)
    }
}

private struct ScreenGlowView: View {
    let style: ScreenGlowController.GlowStyle
    @State private var animate = false

    private var gradient: AngularGradient {
        switch style {
        case .listening:
            return AngularGradient(
                gradient: Gradient(colors: [
                    Color.purple.opacity(0.95),
                    Color.blue.opacity(0.9),
                    Color.cyan.opacity(0.95),
                    Color.purple.opacity(0.95)
                ]),
                center: .center
            )
        case .processing:
            return AngularGradient(
                gradient: Gradient(colors: [
                    Color.orange.opacity(0.8),
                    Color.red.opacity(0.7),
                    Color.pink.opacity(0.8),
                    Color.orange.opacity(0.8)
                ]),
                center: .center
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .strokeBorder(gradient, lineWidth: animate ? 26 : 18)
                    .blur(radius: 30)
                    .opacity(animate ? 0.85 : 0.45)
                    .animation(
                        .easeInOut(duration: 1.1)
                            .repeatForever(autoreverses: true),
                        value: animate
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .compositingGroup()
                Rectangle()
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .background(Color.clear)
        .allowsHitTesting(false)
        .onAppear {
            animate = true
        }
    }
}


