//
//  SpeechSynthesisService.swift
//  araui
//
//  Provides text-to-speech playback through the local AraUI backend.
//

import AVFoundation
import Foundation

/// Text-to-speech wrapper for DashScope Qwen3 TTS Flash audio returned by the backend.
final class SpeechSynthesisService: NSObject, AVAudioPlayerDelegate {
    var onSpeakingStateChanged: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let client = BackendClient()
    private var audioPlayer: AVAudioPlayer?
    private var playbackTask: Task<Void, Never>?
    private var playbackID = UUID()
    private var selectedVoiceName: String = "Cherry"

    func getAvailableVoices() -> [(identifier: String, displayName: String, quality: String)] {
        [
            ("Cherry", "Qwen3 TTS Flash - Cherry", "Qwen")
        ]
    }

    func getCurrentVoiceIdentifier() -> String? {
        selectedVoiceName
    }

    func getCurrentVoiceName() -> String? {
        selectedVoiceName
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            stop()
            return
        }

        stop()
        let requestID = UUID()
        playbackID = requestID
        let voice = selectedVoiceName

        playbackTask = Task { [weak self] in
            guard let self else { return }

            do {
                let audioData = try await self.client.synthesizeSpeech(text: trimmed, voice: voice)
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.playbackID == requestID else { return }

                    do {
                        let player = try AVAudioPlayer(data: audioData)
                        player.delegate = self
                        player.prepareToPlay()
                        self.audioPlayer = player

                        if player.play() {
                            self.onSpeakingStateChanged?(true)
                        } else {
                            self.audioPlayer = nil
                            self.onSpeakingStateChanged?(false)
                        }
                    } catch {
                        let message = (error as NSError).localizedDescription
                        print("Failed to play Qwen TTS audio: \(message)")
                        self.audioPlayer = nil
                        self.onSpeakingStateChanged?(false)
                        self.onError?(message)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.playbackID == requestID else { return }
                    let message = (error as NSError).localizedDescription
                    print("Failed to synthesize Qwen TTS audio: \(message)")
                    self.audioPlayer = nil
                    self.onSpeakingStateChanged?(false)
                    self.onError?(message)
                }
            }
        }
    }

    func stop() {
        playbackID = UUID()
        playbackTask?.cancel()
        playbackTask = nil

        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil
        onSpeakingStateChanged?(false)
    }

    func setVoice(_ voiceName: String?) {
        selectedVoiceName = voiceName?.isEmpty == false ? voiceName! : "Cherry"
    }

    func setRate(_ rate: Float) {
        // Qwen TTS playback rate is controlled by the generated audio, not AVAudioPlayer.
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard self?.audioPlayer === player else { return }
            self?.audioPlayer = nil
            self?.onSpeakingStateChanged?(false)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard self?.audioPlayer === player else { return }
            if let error {
                print("Qwen TTS audio decode failed: \(error)")
            }
            self?.audioPlayer = nil
            self?.onSpeakingStateChanged?(false)
        }
    }
}
