//
//  SpeechSynthesisService.swift
//  nova
//
//  Provides text-to-speech playback using macOS `say` command.
//  Direct access to all system voices with high quality.
//

import Foundation

/// Wrapper around macOS `say` command for text-to-speech.
final class SpeechSynthesisService {
    var onSpeakingStateChanged: ((Bool) -> Void)?
    
    private var currentProcess: Process?
    private var selectedVoiceName: String?
    private var speechRate: Int = 200 // words per minute
    
    init() {
        // Don't configure any voice - use system default
        selectedVoiceName = nil
    }
    
    /// Returns all available voices from the `say` command
    func getAvailableVoices() -> [(identifier: String, displayName: String, quality: String)] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", "?"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        var voices: [(String, String, String)] = []
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Parse output like: "Alex                en_US    # Most people recognize me by my voice."
                for line in output.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    
                    // Extract voice name (first word)
                    let components = trimmed.components(separatedBy: .whitespaces)
                    guard let voiceName = components.first else { continue }
                    
                    // Extract language code
                    let languagePattern = try? NSRegularExpression(pattern: "[a-z]{2}_[A-Z]{2}")
                    let range = NSRange(trimmed.startIndex..., in: trimmed)
                    var language = "en_US"
                    if let match = languagePattern?.firstMatch(in: trimmed, range: range),
                       let langRange = Range(match.range, in: trimmed) {
                        language = String(trimmed[langRange])
                    }
                    
                    // Only include English voices
                    guard language.hasPrefix("en") else { continue }
                    
                    // Determine quality badge
                    let quality: String
                    let badge: String
                    if voiceName.contains("Premium") || ["Samantha", "Karen", "Daniel", "Fiona"].contains(voiceName) {
                        quality = "Premium"
                        badge = " ⭐️"
                    } else {
                        quality = "Default"
                        badge = ""
                    }
                    
                    let displayName = "\(voiceName) (\(language))\(badge)"
                    voices.append((voiceName, displayName, quality))
                }
            }
        } catch {
            print("⚠️ Failed to get voices: \(error)")
        }
        
        return voices.sorted { $0.1 < $1.1 }
    }
    
    /// Returns the currently selected voice name
    func getCurrentVoiceIdentifier() -> String? {
        return selectedVoiceName
    }
    
    /// Returns the currently selected voice display name
    func getCurrentVoiceName() -> String? {
        return selectedVoiceName
    }
    
    /// Stops any current utterance and speaks the supplied text.
    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            stop()
            return
        }
        
        // Stop any current speech
        stop()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            
            var args: [String] = []
            
            // Add voice selection only if explicitly set
            if let voice = self.selectedVoiceName {
                args.append(contentsOf: ["-v", voice])
            }
            // Note: Not adding rate to use system default speed
            
            // Add text
            args.append(trimmed)
            
            process.arguments = args
            
            // Set up termination handler
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.onSpeakingStateChanged?(false)
                    self?.currentProcess = nil
                }
            }
            
            self.currentProcess = process
            
            do {
                try process.run()
                DispatchQueue.main.async {
                    self.onSpeakingStateChanged?(true)
                }
                process.waitUntilExit()
            } catch {
                print("⚠️ Failed to run say command: \(error)")
                DispatchQueue.main.async {
                    self.onSpeakingStateChanged?(false)
                    self.currentProcess = nil
                }
            }
        }
    }
    
    /// Cancels any active speech.
    func stop() {
        if let process = currentProcess, process.isRunning {
            process.terminate()
            currentProcess = nil
            onSpeakingStateChanged?(false)
        }
    }
    
    /// Allows callers to pick a specific voice by name. `nil` resets to default.
    func setVoice(_ voiceName: String?) {
        if let name = voiceName {
            selectedVoiceName = name
        } else {
            configureDefaultVoice()
        }
    }
    
    /// Adjusts playback rate in words per minute (default 200). Range roughly 90...720.
    func setRate(_ rate: Float) {
        speechRate = Int(max(90, min(720, rate)))
    }
    
    /// Adjusts playback volume (0.0 – 1.0). Note: `say` command doesn't support volume directly.
    func setVolume(_ volume: Float) {
        // The say command doesn't have a volume parameter
        // Could use system volume but that affects everything
    }
    
    private func configureDefaultVoice() {
        // Use system default voice (no selection)
        selectedVoiceName = nil
        print("🔊 Using system default voice")
    }
}


