//
//  SpeechRecognitionService.swift
//  nova
//
//  Provides live microphone transcription via Apple's Speech framework.
//

import Foundation
import AVFoundation
import Speech
import CoreAudio

protocol SpeechRecognitionServiceDelegate: AnyObject {
    func speechService(_ svc: SpeechRecognitionService, didUpdatePartial text: String)
    func speechService(_ svc: SpeechRecognitionService, didFinishWith text: String)
    func speechService(_ svc: SpeechRecognitionService, didFail error: Error)
    func speechServiceDidChangeState(_ svc: SpeechRecognitionService, isRunning: Bool)
}

final class SpeechRecognitionService {
    weak var delegate: SpeechRecognitionServiceDelegate?
    var locale: Locale = Locale(identifier: "en-US")

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer? { SFSpeechRecognizer(locale: locale) }
    private var isCancelling: Bool = false
    #if os(macOS)
    private var preferredInputDeviceUID: String?
    #endif

    private(set) var isRunning: Bool = false {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.speechServiceDidChangeState(self, isRunning: self.isRunning)
            }
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        print("🎤 [MIC DEBUG] Requesting speech recognition authorization...")
        SFSpeechRecognizer.requestAuthorization { status in
            print("🎤 [MIC DEBUG] Authorization status: \(status.rawValue) (\(status == .authorized ? "✅ Authorized" : "❌ Not Authorized"))")
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func start() throws {
        guard isRunning == false else { return }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("❌ [MIC DEBUG] Speech recognizer unavailable")
            throw NSError(domain: "SpeechRecognitionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }
        isCancelling = false
        print("✅ [MIC DEBUG] Speech recognizer available")

        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // No strict on-device requirement per plan; system decides
        recognitionRequest = request
        print("✅ [MIC DEBUG] Recognition request created")

        // IMPORTANT: Set input device BEFORE creating recognition task
        // This ensures the audio engine picks up the correct microphone
        #if os(macOS)
        if let uid = preferredInputDeviceUID, setInputDeviceByUID(uid) {
            print("🎤 [MIC DEBUG] Preferred input set via UID: \(uid)")
        } else {
            setBuiltInMicrophone()
        }
        
        // Stop and recreate the audio engine to force it to use the new device
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        audioEngine = AVAudioEngine()
        print("🎤 [MIC DEBUG] Audio engine RECREATED to pick up new default device")
        // Give the system time to update the default input device
        Thread.sleep(forTimeInterval: 0.15)
        #endif

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                print("🎤 [MIC DEBUG] Transcription: \(text) (isFinal: \(result.isFinal))")
                if result.isFinal {
                    DispatchQueue.main.async {
                        self.delegate?.speechService(self, didFinishWith: text)
                    }
                    self.stop()
                } else {
                    DispatchQueue.main.async {
                        self.delegate?.speechService(self, didUpdatePartial: text)
                    }
                }
            } else if let error = error {
                if self.isCancelling {
                    // Ignore expected cancellation error triggered by user stop
                    print("⚠️ [MIC DEBUG] Cancelling - ignoring error")
                    self.isCancelling = false
                    return
                }
                print("❌ [MIC DEBUG] Recognition error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.delegate?.speechService(self, didFail: error)
                }
                self.stop()
            }
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        
        // Print detailed audio input information
        print("🎤 [MIC DEBUG] =================================")
        print("🎤 [MIC DEBUG] Audio Input Device Information:")
        print("🎤 [MIC DEBUG] Sample Rate: \(format.sampleRate) Hz")
        print("🎤 [MIC DEBUG] Channel Count: \(format.channelCount)")
        print("🎤 [MIC DEBUG] Format: \(format)")
        
        #if os(macOS)
        let inputDevice = audioEngine.inputNode.auAudioUnit.deviceID
        print("🎤 [MIC DEBUG] Input Device ID: \(inputDevice)")
        
        // Get the name of the selected microphone using CoreAudio
        let selectedMicName = getAudioDeviceName(deviceID: inputDevice)
        print("🎤 [MIC DEBUG] 🎯 SELECTED MICROPHONE: \(selectedMicName)")
        
        // Get default input device
        let defaultInputDevice = getDefaultInputDevice()
        print("🎤 [MIC DEBUG] Default System Input Device ID: \(defaultInputDevice)")
        let defaultMicName = getAudioDeviceName(deviceID: defaultInputDevice)
        print("🎤 [MIC DEBUG] Default System Input Name: \(defaultMicName)")
        
        if inputDevice == defaultInputDevice {
            print("🎤 [MIC DEBUG] ✅ Using system default microphone")
        } else {
            print("🎤 [MIC DEBUG] ⚠️ Using non-default microphone - ENGINE DID NOT PICK UP CHANGE!")
            print("🎤 [MIC DEBUG] ❌ PROBLEM: Audio engine is using \(selectedMicName) instead of \(defaultMicName)")
        }
        
        // Extra verification: Check if we're using the built-in mic
        let selectedUID = getAudioDeviceUID(deviceID: inputDevice)
        if selectedUID == "BuiltInMicrophoneDevice" || selectedMicName.contains("MacBook Pro Microphone") {
            print("🎤 [MIC DEBUG] ✅✅✅ VERIFIED: Using MacBook Pro built-in microphone!")
        } else {
            print("🎤 [MIC DEBUG] ❌❌❌ ERROR: Still not using built-in microphone!")
            print("🎤 [MIC DEBUG] Currently using: \(selectedMicName) (UID: \(selectedUID))")
        }
        
        // Print available audio devices
        let devices = AVCaptureDevice.devices(for: .audio)
        print("🎤 [MIC DEBUG] All Available Audio Devices:")
        for device in devices {
            print("🎤 [MIC DEBUG]   - \(device.localizedName) (uniqueID: \(device.uniqueID))")
        }
        #endif
        print("🎤 [MIC DEBUG] =================================")
        
        var bufferCount = 0
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
            bufferCount += 1
            
            // Calculate audio level from buffer
            let channelData = buffer.floatChannelData?[0]
            let frames = buffer.frameLength
            var sum: Float = 0.0
            if let data = channelData {
                for i in 0..<Int(frames) {
                    sum += abs(data[i])
                }
            }
            let average = sum / Float(frames)
            
            // Print every 50th buffer to avoid spam
            if bufferCount % 50 == 0 {
                print("🎤 [MIC DEBUG] Buffer #\(bufferCount) - Avg Level: \(String(format: "%.4f", average)) - Time: \(when.sampleTime)")
            }
            
            self?.recognitionRequest?.append(buffer)
        }
        
        print("✅ [MIC DEBUG] Audio tap installed")

        audioEngine.prepare()
        try audioEngine.start()
        print("✅ [MIC DEBUG] Audio engine started successfully")
        isRunning = true
    }

    func stop() {
        guard isRunning else { 
            print("⚠️ [MIC DEBUG] Stop called but not running")
            return 
        }
        print("🛑 [MIC DEBUG] Stopping speech recognition...")
        isCancelling = true
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        #if os(iOS) || os(tvOS) || os(watchOS)
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) } catch {}
        #endif
        isRunning = false
        print("✅ [MIC DEBUG] Speech recognition stopped")
    }
    
    #if os(macOS)
    // MARK: - CoreAudio Helper Functions
    
    // Public minimal API for UI
    func listInputDevices() -> [(name: String, uid: String)] {
        var results: [(String, String)] = []
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let statusSize = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
        guard statusSize == noErr else { return results }
        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        let statusList = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &devices)
        guard statusList == noErr else { return results }
        for id in devices where isInputDevice(deviceID: id) {
            let name = getAudioDeviceName(deviceID: id)
            let uid = getAudioDeviceUID(deviceID: id)
            results.append((name, uid))
        }
        return results
    }
    
    @discardableResult
    func setPreferredInputDevice(uid: String) -> Bool {
        preferredInputDeviceUID = uid
        return setInputDeviceByUID(uid)
    }
    
    @discardableResult
    private func setInputDeviceByUID(_ uid: String) -> Bool {
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let statusSize = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
        guard statusSize == noErr else { return false }
        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        let statusList = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &devices)
        guard statusList == noErr else { return false }
        for id in devices where isInputDevice(deviceID: id) {
            if getAudioDeviceUID(deviceID: id) == uid {
                setDefaultInputDevice(deviceID: id)
                return true
            }
        }
        return false
    }
    
    private func setBuiltInMicrophone() {
        print("🎤 [MIC DEBUG] Attempting to set built-in MacBook Pro microphone...")
        
        // Get all available audio input devices
        var propertySize: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr else {
            print("🎤 [MIC DEBUG] ❌ Failed to get devices size: \(status)")
            return
        }
        
        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &devices
        )
        
        guard status == noErr else {
            print("🎤 [MIC DEBUG] ❌ Failed to get devices: \(status)")
            return
        }
        
        print("🎤 [MIC DEBUG] Found \(deviceCount) audio devices, searching for built-in microphone...")
        
        // Search for the built-in microphone
        for deviceID in devices {
            let deviceName = getAudioDeviceName(deviceID: deviceID)
            let deviceUID = getAudioDeviceUID(deviceID: deviceID)
            
            print("🎤 [MIC DEBUG] Checking device: \(deviceName) (UID: \(deviceUID))")
            
            // Check if this is an input device
            if !isInputDevice(deviceID: deviceID) {
                print("🎤 [MIC DEBUG]   ↳ Skipping: Not an input device")
                continue
            }
            
            // Look for built-in microphone by UID or name
            if deviceUID == "BuiltInMicrophoneDevice" || 
               deviceName.contains("MacBook Pro Microphone") ||
               deviceName.contains("Built-in Microphone") {
                print("🎤 [MIC DEBUG] ✅ Found built-in microphone: \(deviceName)")
                
                // Set this as the default input device
                setDefaultInputDevice(deviceID: deviceID)
                print("🎤 [MIC DEBUG] ✅ Set \(deviceName) as default input")
                return
            }
        }
        
        print("🎤 [MIC DEBUG] ⚠️ Built-in microphone not found, using system default")
    }
    
    private func getAudioDeviceUID(deviceID: AudioDeviceID) -> String {
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceUID: CFString = "" as CFString
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &deviceUID
        )
        
        if status != noErr {
            return "Unknown"
        }
        
        return deviceUID as String
    }
    
    private func isInputDevice(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var propertySize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &propertySize
        )
        
        guard status == noErr, propertySize > 0 else {
            return false
        }
        
        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }
        
        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            bufferListPointer
        )
        
        guard getStatus == noErr else {
            return false
        }
        
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.count > 0
    }
    
    private func setDefaultInputDevice(deviceID: AudioDeviceID) {
        var deviceIDCopy = deviceID
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDCopy
        )
        
        if status != noErr {
            print("🎤 [MIC DEBUG] ❌ Failed to set default input device: \(status)")
        }
    }
    
    private func getDefaultInputDevice() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        if status != noErr {
            print("🎤 [MIC DEBUG] ❌ Failed to get default input device: \(status)")
        }
        
        return deviceID
    }
    
    private func getAudioDeviceName(deviceID: AudioDeviceID) -> String {
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var deviceName: CFString = "" as CFString
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &deviceName
        )
        
        if status != noErr {
            print("🎤 [MIC DEBUG] ❌ Failed to get device name for ID \(deviceID): \(status)")
            return "Unknown Device (ID: \(deviceID))"
        }
        
        return deviceName as String
    }
    #endif
}


