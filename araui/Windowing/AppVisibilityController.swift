import AppKit
import SwiftUI

@MainActor
final class AppVisibilityController {
    static let shared = AppVisibilityController()

    private init() {}

    private(set) var isCollapsed: Bool = true
    private weak var mainWindow: NSWindow?
    private var iconWC: FloatingIconWindowController?
    private var cachedViewModel: ChatViewModel?

    // Settings
    private let startCollapsedKey = "StartCollapsed"
    private let hideIconWhenExpandedKey = "HideIconWhenExpanded"
    private var hideIconWhenExpanded: Bool {
        UserDefaults.standard.bool(forKey: hideIconWhenExpandedKey)
    }

    // MARK: - Public API

    func registerMainWindow(_ window: NSWindow) {
        mainWindow = window
        window.isExcludedFromWindowsMenu = false
        if isCollapsed {
            window.orderOut(nil)
        } else {
            showMainWindow()
        }
    }

    func ensureIconWindow() {
        if iconWC == nil {
            let vm = resolveViewModel()

            iconWC = FloatingIconWindowController(
                viewModel: vm,
                onClick: { [weak self] in self?.toggle() },
                onDragChanged: { [weak self] translation in
                    self?.iconWC?.beginDragIfNeeded()
                    self?.iconWC?.moveBy(translation: translation)
                },
                onDragEnded: { [weak self] in
                    self?.persistIconPosition()
                    self?.iconWC?.endDrag()
                }
            )
            restoreIconPosition()
            iconWC?.showWindow(nil)
        }
    }

    func collapse() {
        guard isCollapsed == false else { return }
        ensureIconWindow()
        for w in NSApp.windows {
            if w !== iconWC?.window && ScreenGlowController.shared.isGlowWindow(w) == false {
                w.orderOut(nil)
            }
        }
        isCollapsed = true
    }

    func expand() {
        guard isCollapsed else { return }
        if hideIconWhenExpanded {
            hideIconWindow()
        } else {
            showIconWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        showMainWindow()
        isCollapsed = false
    }

    func toggle() { isCollapsed ? expand() : collapse() }

    // MARK: - Icon window helpers

    func hideIconWindow() {
        iconWC?.window?.orderOut(nil)
    }

    func showIconWindow() {
        ensureIconWindow()
        iconWC?.showWindow(nil)
        iconWC?.window?.orderFrontRegardless()
    }

    // MARK: - Startup

    func startupCollapsed() {
        ensureIconWindow()
        isCollapsed = true
        for w in NSApp.windows {
            if w !== iconWC?.window && ScreenGlowController.shared.isGlowWindow(w) == false {
                w.orderOut(nil)
            }
        }
    }

    func startupRespectingSettings() {
        ensureIconWindow()
        let shouldStartCollapsed = UserDefaults.standard.object(forKey: startCollapsedKey) as? Bool ?? false
        if shouldStartCollapsed {
            startupCollapsed()
        } else {
            isCollapsed = false
            if hideIconWhenExpanded {
                hideIconWindow()
            } else {
                showIconWindow()
            }
            NSApp.activate(ignoringOtherApps: true)
            showMainWindow()
        }
    }

    // MARK: - Persistence

    private let positionDefaultsKey = "FloatingIconPosition"

    private func persistIconPosition() {
        guard let window = iconWC?.window else { return }
        let origin = window.frame.origin
        let dict: [String: CGFloat] = ["x": origin.x, "y": origin.y]
        UserDefaults.standard.set(dict, forKey: positionDefaultsKey)
    }

    private func restoreIconPosition() {
        guard let wc = iconWC else { return }
        guard let dict = UserDefaults.standard.object(forKey: positionDefaultsKey) as? [String: CGFloat],
              let x = dict["x"], let y = dict["y"] else {
            placeIconAtDefault()
            return
        }
        let origin = NSPoint(x: x, y: y)
        wc.window?.setFrameOrigin(clampToVisible(origin: origin, size: wc.window?.frame.size ?? NSSize(width: 48, height: 48)))
    }

    private func placeIconAtDefault() {
        guard let wc = iconWC, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = wc.window?.frame.size ?? NSSize(width: 48, height: 48)
        let origin = NSPoint(x: frame.maxX - size.width - 16, y: frame.midY - size.height / 2)
        wc.window?.setFrameOrigin(origin)
    }

    private func showMainWindow() {
        let window = mainWindow ?? NSApp.windows.first { window in
            window !== iconWC?.window && ScreenGlowController.shared.isGlowWindow(window) == false
        }
        window?.makeKeyAndOrderFront(nil)
    }

    private func clampToVisible(origin: NSPoint, size: NSSize) -> NSPoint {
        let screen = iconWC?.window?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        let x = max(visible.minX, min(visible.maxX - size.width, origin.x))
        let y = max(visible.minY, min(visible.maxY - size.height, origin.y))
        return NSPoint(x: x, y: y)
    }

    private func resolveViewModel() -> ChatViewModel {
        if let delegateVM = (NSApp.delegate as? AppDelegate)?.sharedViewModel {
            cachedViewModel = delegateVM
            return delegateVM
        }
        if let cachedViewModel {
            return cachedViewModel
        }
        let fallback = ChatViewModel()
        cachedViewModel = fallback
        return fallback
    }
}

