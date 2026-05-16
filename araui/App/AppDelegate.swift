import AppKit
import Carbon

private func FourCharCode(_ string: String) -> OSType {
    var result: UInt32 = 0
    for scalar in string.unicodeScalars {
        result = (result << 8) + UInt32(scalar.value)
    }
    return OSType(result)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Shared ChatViewModel so auxiliary windows and hotkeys use the same instance
    let sharedViewModel = ChatViewModel()

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandler: EventHandlerRef?
    private var hotKeyCallback: EventHandlerUPP?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the floating icon exists and start according to settings (default collapsed)
        Task { @MainActor in
            AppVisibilityController.shared.ensureIconWindow()
            // Defer to next runloop to allow SwiftUI to create the main window before changing state
            AppVisibilityController.shared.startupRespectingSettings()
        }

        Task(priority: .userInitiated) {
            do {
                try await BackendClient.ensureSession()
            } catch {
                print("Failed to create backend session on launch: \(error.localizedDescription)")
            }
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleScreenConfigChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)

        registerGlobalHotkey()
        ScreenSnippingService.shared.startMonitoring()
    }

    @objc private func handleScreenConfigChanged() {
        // Nudge the icon back into a visible frame if displays change
        Task { @MainActor in
            AppVisibilityController.shared.ensureIconWindow()
        }
    }

    private func registerGlobalHotkey() {
        // Four-character code 'NVAC'
        let signature: OSType = FourCharCode("NVAC")
        let hotKeyID = EventHotKeyID(signature: signature, id: UInt32(1))
        let modifierFlags = UInt32(optionKey)

        let target = GetApplicationEventTarget()
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_X), modifierFlags, hotKeyID, target, 0, &hotKeyRef)

        if status != noErr {
            print("Failed to register global hotkey ⌥X: \(status)")
            return
        } else {
            print("Registered global hotkey ⌥X")
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        hotKeyCallback = { _, eventRef, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            delegate.handleHotkeyEvent(event: eventRef)
            return noErr
        }

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let installStatus = InstallEventHandler(target, hotKeyCallback, 1, &eventType, userData, &hotKeyEventHandler)

        if installStatus != noErr {
            print("Failed to install hotkey handler: \(installStatus)")
        }
    }

    private func handleHotkeyEvent(event: EventRef?) {
        guard let event else { return }
        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        if err == noErr {
            print("Hotkey ⌥X pressed (id: \(hotKeyID.id))")
            DispatchQueue.main.async { [weak self] in
                self?.sharedViewModel.handleGlobalHotkeyPress()
            }
        } else {
            print("Failed to read hotkey event parameter: \(err)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handler = hotKeyEventHandler {
            RemoveEventHandler(handler)
            hotKeyEventHandler = nil
        }
        hotKeyCallback = nil
        ScreenSnippingService.shared.stopMonitoring()
    }
}


