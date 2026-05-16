//
//  AccessibilityCaptureService.swift
//  nova
//
//  Continuously captures accessible text from the frontmost app window.
//

import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo

struct RecognizedApp {
    let name: String
    let icon: NSImage?
}

final class AccessibilityCaptureService {
    var onCapture: ((String) -> Void)?
    var onRecognizedAppChange: ((RecognizedApp?) -> Void)?
    var onScreenshot: ((NSImage) -> Void)?

    private var timer: Timer?
    private var lastHash: Int?
    private let pollInterval: TimeInterval = 2.0
    private let maxChars: Int = 8000
    private var lastFrontmostBundleId: String?
    private var lastNonSelfAppBundleId: String?
    private var lastNonSelfAppPid: pid_t?
    private var lastNonSelfAppSnapshot: RecognizedApp?

    @discardableResult
    func start() -> Bool {
        guard isTrustedOrPrompt() else { return false }
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        tick()
        return true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        emitFrontmostAppIfChanged()
        guard let text = captureFrontmostWindowText(), text.isEmpty == false else { return }
        let clipped = String(text.prefix(maxChars))
        let hash = clipped.hashValue
        guard hash != lastHash else { return }
        lastHash = hash
        onCapture?(clipped)
    }

    private func isTrustedOrPrompt(promptIfNeeded: Bool = true) -> Bool {
        let options: CFDictionary
        if promptIfNeeded {
            options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        } else {
            options = [:] as CFDictionary
        }
        return AXIsProcessTrustedWithOptions(options)
    }

    private func captureFrontmostWindowText() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        if let myBundle = Bundle.main.bundleIdentifier,
           let frontBundle = frontApp.bundleIdentifier,
           frontBundle == myBundle {
            // Avoid capturing our own app's UI (e.g., header label "AraUI")
            return nil
        }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // Prefer the focused UI element (often the text editor in apps like Notes)
        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        var rootElement: AXUIElement?
        if focusedResult == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            rootElement = (focusedRef as! AXUIElement)
        } else {
            // Fallback to the focused window
            var windowRef: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
            if result == .success, let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                rootElement = (windowRef as! AXUIElement)
            }
        }
        guard let element = rootElement else { return nil }

        var visited = Set<UnsafeMutableRawPointer>()
        let text = collectText(from: element, visited: &visited)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func emitFrontmostAppIfChanged() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            if lastFrontmostBundleId != nil {
                lastFrontmostBundleId = nil
                onRecognizedAppChange?(nil)
            }
            return
        }

        let bundleId = app.bundleIdentifier ?? String(app.processIdentifier)
        guard bundleId != lastFrontmostBundleId else { return }
        lastFrontmostBundleId = bundleId

        let myBundle = Bundle.main.bundleIdentifier
        let isSelf = (myBundle != nil && bundleId == myBundle)

        if isSelf {
            // When AraUI is frontmost, continue showing the last non-self app snapshot (if any)
            if let snapshot = lastNonSelfAppSnapshot {
                onRecognizedAppChange?(snapshot)
            }
            return
        }

        let name = app.localizedName ?? bundleId
        var icon: NSImage? = nil
        if let url = app.bundleURL {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        }

        let snapshot = RecognizedApp(name: name, icon: icon)
        lastNonSelfAppSnapshot = snapshot
        lastNonSelfAppBundleId = app.bundleIdentifier
        lastNonSelfAppPid = app.processIdentifier
        onRecognizedAppChange?(snapshot)

        // Capture a screenshot of the focused window for the new frontmost app (non-self)
        let pid = app.processIdentifier
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            if let image = await self.captureFocusedWindowScreenshot(pid: pid) {
                DispatchQueue.main.async { [weak self] in
                    self?.onScreenshot?(image)
                }
            }
        }
    }

    private func collectText(from element: AXUIElement, visited: inout Set<UnsafeMutableRawPointer>) -> String {
        let key = Unmanaged.passUnretained(element).toOpaque()
        if visited.contains(key) { return "" }
        visited.insert(key)

        func attribute(_ name: CFString) -> Any? {
            var value: CFTypeRef?
            let code = AXUIElementCopyAttributeValue(element, name, &value)
            return code == .success ? value : nil
        }
        func attribute(_ name: String) -> Any? {
            attribute(name as CFString)
        }

        // Skip secure/protected text fields
        if let isProtected = attribute("AXValueProtected") as? Bool, isProtected {
            return ""
        }
        if let role = attribute(kAXRoleAttribute) as? String, role == "AXSecureTextField" {
            return ""
        }

        // Try to pull full text using parameterized range if supported
        if let numChars = attribute(kAXNumberOfCharactersAttribute) as? NSNumber, numChars.intValue > 0 {
            var range = CFRange(location: 0, length: numChars.intValue)
            if let rangeValue = AXValueCreate(.cfRange, &range) {
                var out: CFTypeRef?
                let code = AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &out)
                if code == .success, let str = out as? String, str.isEmpty == false {
                    return str
                }
            }
        }

        // Prefer value attribute (works for text fields/areas/web areas)
        if let value = attribute(kAXValueAttribute) as? String {
            return value
        }
        if let attr = attribute(kAXValueAttribute) as? NSAttributedString {
            return attr.string
        }

        // Fallback to title for static text/buttons/etc.
        if let title = attribute(kAXTitleAttribute) as? String, title.isEmpty == false {
            return title
        }

        // Recurse into children
        var aggregate = ""
        // Prefer visible children if available
        let childrenList: [AXUIElement]? = (attribute(kAXVisibleChildrenAttribute) as? [AXUIElement]) ?? (attribute(kAXChildrenAttribute) as? [AXUIElement])
        if let children = childrenList {
            for child in children {
                let t = collectText(from: child, visited: &visited)
                if t.isEmpty == false {
                    aggregate += (aggregate.isEmpty ? "" : "\n") + t
                }
            }
        }
        return aggregate
    }
}

extension AccessibilityCaptureService {
    struct Snapshot {
        let contextText: String?
        let screenshot: NSImage?
        let app: RecognizedApp?
    }

    enum SnapshotError: Error {
        case permissionDenied
    }

    func captureFrontmostSnapshot() async throws -> Snapshot {
        guard isTrustedOrPrompt(promptIfNeeded: false) else {
            throw SnapshotError.permissionDenied
        }

        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return Snapshot(contextText: nil, screenshot: nil, app: nil)
        }

        let myBundle = Bundle.main.bundleIdentifier
        let isSelf = (myBundle != nil && frontApp.bundleIdentifier == myBundle)

        let context = captureFrontmostWindowText()

        let appSnapshot: RecognizedApp?
        if isSelf {
            appSnapshot = lastNonSelfAppSnapshot
        } else {
            let name = frontApp.localizedName ?? (frontApp.bundleIdentifier ?? String(frontApp.processIdentifier))
            var icon: NSImage? = nil
            if let url = frontApp.bundleURL {
                icon = NSWorkspace.shared.icon(forFile: url.path)
            }
            appSnapshot = RecognizedApp(name: name, icon: icon)
        }

        let screenshot = await captureFrontmostScreenshot(pid: frontApp.processIdentifier)
        return Snapshot(contextText: context, screenshot: screenshot, app: appSnapshot)
    }

    private func captureFrontmostScreenshot(pid: pid_t) async -> NSImage? {
        await withCheckedContinuation { continuation in
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = await self.captureFocusedWindowScreenshot(pid: pid)
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: - Screen recording permission
    private func ensureScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    // MARK: - Focused window screenshot capture
    fileprivate func captureFocusedWindowScreenshot(pid: pid_t) async -> NSImage? {
        guard ensureScreenRecordingPermission() else { return nil }

        let appElement = AXUIElementCreateApplication(pid)

        // Try to get the focused window and its window number
        var windowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
        if windowResult == .success, let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
            let windowEl = windowRef as! AXUIElement
            var numberRef: CFTypeRef?
            let numberResult = AXUIElementCopyAttributeValue(windowEl, "AXWindowNumber" as CFString, &numberRef)
            if numberResult == .success, let anyRef = numberRef, CFGetTypeID(anyRef) == CFNumberGetTypeID() {
                let cfNumber = anyRef as! CFNumber
                var windowNumber: Int32 = 0
                if CFNumberGetValue(cfNumber, .sInt32Type, &windowNumber) {
                    return await captureWithScreenCaptureKit(targetPid: pid, targetWindowId: CGWindowID(UInt32(windowNumber)))
                }
            }
        }
        // Fallback: enumerate shareable windows for the PID and capture the first on-screen match
        return await captureWithScreenCaptureKit(targetPid: pid, targetWindowId: nil)
    }

    // MARK: - ScreenCaptureKit path
    private func captureWithScreenCaptureKit(targetPid: pid_t, targetWindowId: CGWindowID?) async -> NSImage? {
        guard #available(macOS 12.3, *) else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // Resolve target SCWindow
            let targetWindow: SCWindow?
            if let windowId = targetWindowId {
                targetWindow = content.windows.first(where: { $0.windowID == windowId && $0.owningApplication?.processID == targetPid })
            } else {
                targetWindow = content.windows.first(where: { $0.owningApplication?.processID == targetPid })
            }

            guard let scWindow = targetWindow else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            // Match window size; if zero, default to 1280x800
            let width = Int(max(scWindow.frame.width, 1))
            let height = Int(max(scWindow.frame.height, 1))
            config.width = width
            config.height = height
            config.queueDepth = 1
            config.showsCursor = false
            config.capturesAudio = false
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

            let grabber = SingleFrameGrabber()
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(grabber, type: .screen, sampleHandlerQueue: DispatchQueue.global(qos: .userInitiated))
            try await stream.startCapture()

            // Wait up to 1s for the first frame
            let timeout: DispatchTime = .now() + .seconds(1)
            _ = grabber.semaphore.wait(timeout: timeout)

            try? await stream.stopCapture()
            try? stream.removeStreamOutput(grabber, type: .screen)

            if let cgImage = grabber.image {
                return NSImage(cgImage: cgImage, size: .zero)
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Helpers
    private final class SingleFrameGrabber: NSObject, SCStreamOutput {
        let semaphore = DispatchSemaphore(value: 0)
        private(set) var image: CGImage?
        private static let ciContext = CIContext(options: nil)

        func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
            guard outputType == .screen, image == nil else { return }
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            let rect = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
            if let cg = Self.ciContext.createCGImage(ciImage, from: rect) {
                image = cg
                semaphore.signal()
            }
        }
    }

    /// Capture the currently selected text from the focused UI element of the frontmost app.
    /// Falls back to selected range extraction when plain selected text is unavailable.
    /// Returns a clipped string (up to maxChars) or nil if not available/secure.
    func captureSelectedTextOnce() -> String? {
        guard isTrustedOrPrompt() else { return nil }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        return captureSelectedText(appPid: frontApp.processIdentifier)
    }

    /// Capture selected text from the last non-self app (if known), even when AraUI is frontmost.
    func captureSelectedTextFromLastAppOnce() -> String? {
        guard isTrustedOrPrompt() else { return nil }
        // Prefer PID for stability; if missing, try to resolve by bundle id
        var targetPid: pid_t?
        if let pid = lastNonSelfAppPid {
            targetPid = pid
        } else if let bid = lastNonSelfAppBundleId {
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bid }) {
                targetPid = app.processIdentifier
            }
        }
        guard let pid = targetPid else { return nil }
        return captureSelectedText(appPid: pid)
    }

    private func captureSelectedText(appPid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(appPid)

        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
        var focused: AXUIElement?
        if focusedResult == .success, let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            focused = (focusedRef as! AXUIElement)
        } else {
            // Fallback to focused window
            var windowRef: CFTypeRef?
            let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef)
            if windowResult == .success, let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID() {
                focused = (windowRef as! AXUIElement)
            }
        }
        guard let focused else { return nil }

        func attribute(_ name: CFString) -> Any? {
            var value: CFTypeRef?
            let code = AXUIElementCopyAttributeValue(focused, name, &value)
            return code == .success ? value : nil
        }
        func attribute(_ name: String) -> Any? { attribute(name as CFString) }

        // Skip secure/protected fields
        if let isProtected = attribute("AXValueProtected") as? Bool, isProtected { return nil }
        if let role = attribute(kAXRoleAttribute) as? String, role == "AXSecureTextField" { return nil }

        // Prefer kAXSelectedTextAttribute when available
        if let selected = attribute(kAXSelectedTextAttribute) as? String, selected.isEmpty == false {
            return String(selected.prefix(maxChars))
        }

        // Fallback: derive from selected range
        if let rangeAny = attribute(kAXSelectedTextRangeAttribute) {
            let rangeCF = rangeAny as CFTypeRef
            if CFGetTypeID(rangeCF) == AXValueGetTypeID() {
                let rangeValue = rangeCF as! AXValue
                var range = CFRange()
                if AXValueGetType(rangeValue) == .cfRange, AXValueGetValue(rangeValue, .cfRange, &range) {
                    var out: CFTypeRef?
                    let code = AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &out)
                    if code == .success, let str = out as? String, str.isEmpty == false {
                        return String(str.prefix(maxChars))
                    }
                }
            }
        }

        // As a final fallback, try the value attribute
        if let value = attribute(kAXValueAttribute) as? String, value.isEmpty == false {
            return String(value.prefix(maxChars))
        }
        if let attr = attribute(kAXValueAttribute) as? NSAttributedString, attr.string.isEmpty == false {
            return String(attr.string.prefix(maxChars))
        }
        return nil
    }
}
