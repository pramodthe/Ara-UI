//
//  ChatViewModel.swift
//  nova
//
//  Orchestrates chat state and streaming.
//

import Foundation
import AppKit
import Speech
import AVFoundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var input: String = ""
    @Published var isStreaming: Bool = false
    @Published var errorMessage: String?
    @Published var autoCaptureEnabled: Bool = false
    @Published var recognizedApp: RecognizedApp?
    @Published var pendingContext: String?
    @Published var screenshot: NSImage?
    @Published var isListening: Bool = false
    @Published var partialTranscript: String?
    @Published var isHotkeyCaptureActive: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var isMuted: Bool = false
    #if os(macOS)
    @Published var inputDevices: [(name: String, uid: String)] = []
    @Published var selectedInputDeviceUID: String? = nil
    #endif

    private let client = BackendClient()
    private let capturer = AccessibilityCaptureService()
    private let speech = SpeechRecognitionService()
    private let speechSynthesizer = SpeechSynthesisService()

    private var hotkeyTask: Task<Void, Never>?

    init() {
        // Optional: seed a greeting
        messages = []
        
        // Set up speech synthesizer callback
        speechSynthesizer.onSpeakingStateChanged = { [weak self] isSpeaking in
            Task { @MainActor in
                self?.isSpeaking = isSpeaking
            }
        }

        capturer.onCapture = { [weak self] text in
            guard let self else { return }
            print("Captured context (\(text.count) chars)\n\(text)\n---")
            // Replace any existing context with the most recent capture
            self.pendingContext = String(text.prefix(10000))
        }

        capturer.onRecognizedAppChange = { [weak self] app in
            guard let self else { return }
            self.recognizedApp = app
        }

        capturer.onScreenshot = { [weak self] image in
            guard let self else { return }
            self.screenshot = image
            DispatchQueue.global(qos: .utility).async {
                if let url = self.saveScreenshotToDisk(image: image) {
                    print("Screenshot saved at: \(url.path)")
                } else {
                    print("Failed to save screenshot to disk")
                }
            }
        }
        speech.delegate = self

        setAutoCapture(false)

        #if os(macOS)
        refreshInputDevices()
        #endif
        
        loadSavedVoice()
    }

    func loadApiKeyExists() -> Bool {
        // Gemini API key no longer required with backend integration.
        // Keeping return value `true` preserves existing UI flows without prompting for a key.
        return true
    }

    func clearChat() {
        messages.removeAll()
        errorMessage = nil
        speechSynthesizer.stop()
    }
    
    func stopSpeaking() {
        speechSynthesizer.stop()
    }
    
    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            // Stop any current speech when muting
            speechSynthesizer.stop()
        }
    }

    #if os(macOS)
    func refreshInputDevices() {
        inputDevices = speech.listInputDevices()
        if selectedInputDeviceUID == nil {
            // Default to built-in mic if present
            if let builtIn = inputDevices.first(where: { $0.uid == "BuiltInMicrophoneDevice" }) {
                selectedInputDeviceUID = builtIn.uid
            } else {
                selectedInputDeviceUID = inputDevices.first?.uid
            }
        }
    }
    
    func applySelectedInputDevice() {
        guard let uid = selectedInputDeviceUID else { return }
        _ = speech.setPreferredInputDevice(uid: uid)
        if isListening {
            stopListening()
            startListening()
        }
    }
    #endif

    func send() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, isStreaming == false else { return }
        errorMessage = nil

        let userMessage = Message(role: .user, text: trimmed)
        messages.append(userMessage)
        input = ""

        let assistant = Message(role: .model, text: "")
        messages.append(assistant)
        let assistantIndex = messages.count - 1

        isStreaming = true
        ScreenGlowController.shared.showGlow(style: .processing)
        do {
            let hidden = pendingContext
            pendingContext = nil

            var imageData: Data?
            var mimeType: String?
            if let image = screenshot, let jpeg = toJPEGData(image) {
                imageData = jpeg
                mimeType = "image/jpeg"
                // Clear screenshot so it isn't reused unintentionally
                screenshot = nil
            }

            // Previously streamed via Gemini; now use backend single-response flow.
            let reply = try await client.sendMessage(
                text: userMessage.text,
                inlineImageData: imageData,
                mimeType: mimeType,
                hiddenContext: hidden
            )
            messages[assistantIndex].text = reply
            if !isMuted {
                speechSynthesizer.speak(reply)
            }
        } catch {
            errorMessage = (error as NSError).localizedDescription
        }
        isStreaming = false
        ScreenGlowController.shared.hideGlow()
    }

    func sendTranscribedText(_ text: String) async {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, isStreaming == false else { return }
        input = text
        await send()
    }

    func toggleMic() {
        print("🎤 [VIEWMODEL DEBUG] toggleMic called, isListening: \(isListening)")
        if isListening {
            print("🎤 [VIEWMODEL DEBUG] Stopping listening...")
            stopListening(commitPartial: true, send: false)
        } else {
            print("🎤 [VIEWMODEL DEBUG] Starting listening...")
            startListening()
        }
    }

    func handleGlobalHotkeyPress() {
        if isHotkeyCaptureActive {
            if isListening {
                stopListening(commitPartial: true, send: true)
            } else {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isHotkeyCaptureActive = false
                }
                ScreenGlowController.shared.hideGlow()
            }
        } else {
            startHotkeyCapture()
        }
    }

    private func startHotkeyCapture() {
        hotkeyTask?.cancel()
        hotkeyTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                AppVisibilityController.shared.ensureIconWindow()
                ScreenGlowController.shared.showGlow()
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.isHotkeyCaptureActive = true
                }
            }
            let started = await requestAndStartListening()
            if started {
                await fetchFrontmostSnapshot()
            }
        }
    }

    @discardableResult
    private func requestAndStartListening() async -> Bool {
        await withCheckedContinuation { continuation in
            speech.requestAuthorization { [weak self] granted in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                Task { @MainActor in
                    if granted == false {
                        self.errorMessage = "Microphone/Speech permission required in System Settings."
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.isHotkeyCaptureActive = false
                            ScreenGlowController.shared.hideGlow()
                        }
                        continuation.resume(returning: false)
                        return
                    }
                    do {
                        try self.speech.start()
                        self.isListening = true
                        ScreenGlowController.shared.showGlow()
                        continuation.resume(returning: true)
                    } catch {
                        self.errorMessage = (error as NSError).localizedDescription
                        withAnimation(.easeInOut(duration: 0.3)) {
                            self.isHotkeyCaptureActive = false
                            ScreenGlowController.shared.hideGlow()
                        }
                        continuation.resume(returning: false)
                    }
                }
            }
        }
    }

    private func fetchFrontmostSnapshot() async {
        do {
            let snapshot = try await capturer.captureFrontmostSnapshot()
            await MainActor.run {
                if let context = snapshot.contextText, context.isEmpty == false {
                    pendingContext = context
                }
                if let image = snapshot.screenshot {
                    screenshot = image
                }
                if let app = snapshot.app {
                    recognizedApp = app
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = (error as NSError).localizedDescription
            }
        }
    }

    private func startListening() {
        print("🎤 [VIEWMODEL DEBUG] startListening() called, requesting authorization...")
        speech.requestAuthorization { [weak self] granted in
            guard let self else {
                print("🎤 [VIEWMODEL DEBUG] ❌ Self is nil in authorization callback")
                return
            }
            print("🎤 [VIEWMODEL DEBUG] Authorization callback received, granted: \(granted)")
            Task { @MainActor in
                if granted == false {
                    print("🎤 [VIEWMODEL DEBUG] ❌ Authorization denied")
                    self.errorMessage = "Microphone/Speech permission required in System Settings."
                    return
                }
                print("🎤 [VIEWMODEL DEBUG] Authorization granted, starting speech service...")
                do {
                    try self.speech.start()
                    print("🎤 [VIEWMODEL DEBUG] ✅ Speech service started successfully")
                    self.isListening = true
                    ScreenGlowController.shared.showGlow()
                } catch {
                    print("🎤 [VIEWMODEL DEBUG] ❌ Failed to start speech service: \(error.localizedDescription)")
                    self.errorMessage = (error as NSError).localizedDescription
                }
            }
        }
    }

    private func stopListening(commitPartial: Bool = false, send: Bool = false) {
        speech.stop()
        if commitPartial {
            let text = partialTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty == false {
                if send {
                    Task { await sendTranscribedText(text) }
                } else {
                    input = text
                }
            }
        }
        isListening = false
        partialTranscript = nil
        ScreenGlowController.shared.hideGlow()
    }

    func setAutoCapture(_ enabled: Bool) {
        autoCaptureEnabled = enabled
        if enabled {
            let started = capturer.start()
            if started == false {
                errorMessage = "Accessibility permission required. Enable AraUI in System Settings → Privacy & Security → Accessibility."
            }
        } else {
            capturer.stop()
        }
    }

    func captureSelection() {
        // Try last non-self app first (so switching back to AraUI doesn't clear context)
        if let text = capturer.captureSelectedTextFromLastAppOnce(), text.isEmpty == false {
            pendingContext = text
            print("Selected context (\(text.count) chars)\n\(text)\n---")
        } else if let text = capturer.captureSelectedTextOnce(), text.isEmpty == false {
            pendingContext = text
            print("Selected context (\(text.count) chars)\n\(text)\n---")
        } else {
            errorMessage = "No selected text found in the frontmost app."
        }
    }

    func clearPendingContext() {
        pendingContext = nil
    }
    
    // MARK: - Voice Selection
    func getAvailableVoices() -> [(identifier: String, displayName: String, quality: String)] {
        return speechSynthesizer.getAvailableVoices()
    }
    
    func getCurrentVoiceIdentifier() -> String? {
        return speechSynthesizer.getCurrentVoiceIdentifier()
    }
    
    func setVoice(_ identifier: String?) {
        speechSynthesizer.setVoice(identifier)
        if let id = identifier {
            UserDefaults.standard.set(id, forKey: "SelectedVoiceIdentifier")
        } else {
            UserDefaults.standard.removeObject(forKey: "SelectedVoiceIdentifier")
        }
    }
    
    func loadSavedVoice() {
        if let savedIdentifier = UserDefaults.standard.string(forKey: "SelectedVoiceIdentifier") {
            speechSynthesizer.setVoice(savedIdentifier)
        }
    }

    // MARK: - Screenshot saving
    private func saveScreenshotToDisk(image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }

        let fm = FileManager.default
        let baseSupportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let targetDir = baseSupportDir.appendingPathComponent("AraUI/Screenshots", isDirectory: true)

        let makeDirectory: () -> URL? = {
            do {
                try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
                return targetDir
            } catch {
                print("Failed to create screenshot directory: \(error.localizedDescription)")
                return nil
            }
        }

        let resolvedDir = makeDirectory() ?? fm.temporaryDirectory
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "screenshot_\(timestamp).png"
        let fileURL = resolvedDir.appendingPathComponent(filename)

        do {
            try png.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("Failed to write screenshot to \(fileURL.path): \(error.localizedDescription)")
            let fallbackURL = fm.temporaryDirectory.appendingPathComponent("AraUI_screenshot_\(timestamp).png")
            do {
                try png.write(to: fallbackURL, options: .atomic)
                return fallbackURL
            } catch {
                print("Failed to write screenshot to temporary directory: \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Image encoding
    private func toJPEGData(_ image: NSImage, quality: Double = 0.9) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}

// MARK: - SpeechRecognitionServiceDelegate
extension ChatViewModel: SpeechRecognitionServiceDelegate {
    func speechService(_ svc: SpeechRecognitionService, didUpdatePartial text: String) {
        print("🎤 [DELEGATE] didUpdatePartial: '\(text)'")
        partialTranscript = text
    }

    func speechService(_ svc: SpeechRecognitionService, didFinishWith text: String) {
        print("🎤 [DELEGATE] didFinishWith: '\(text)'")
        isListening = false
        partialTranscript = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            isHotkeyCaptureActive = false
        }
        ScreenGlowController.shared.hideGlow()
        // Populate the input field with the final transcript instead of auto-sending
        input = text
        print("🎤 [DELEGATE] Input field set to: '\(input)'")
    }

    func speechService(_ svc: SpeechRecognitionService, didFail error: Error) {
        print("🎤 [DELEGATE] didFail: \(error.localizedDescription)")
        isListening = false
        partialTranscript = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            isHotkeyCaptureActive = false
        }
        ScreenGlowController.shared.hideGlow()
        errorMessage = (error as NSError).localizedDescription
    }

    func speechServiceDidChangeState(_ svc: SpeechRecognitionService, isRunning: Bool) {
        print("🎤 [DELEGATE] didChangeState: isRunning=\(isRunning)")
        isListening = isRunning
        if isRunning == false {
            withAnimation(.easeInOut(duration: 0.3)) {
                isHotkeyCaptureActive = false
            }
            ScreenGlowController.shared.hideGlow()
        } else {
            ScreenGlowController.shared.showGlow()
        }
    }
}

