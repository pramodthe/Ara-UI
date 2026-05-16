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
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    func start() throws {
        guard isRunning == false else { return }
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw NSError(domain: "SpeechRecognitionService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"])
        }
        isCancelling = false

        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // No strict on-device requirement per plan; system decides
        recognitionRequest = request

        #if os(macOS)
        if let uid = preferredInputDeviceUID {
            _ = setInputDeviceByUID(uid)
        } else {
            setBuiltInMicrophone()
        }
        
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        audioEngine = AVAudioEngine()
        #endif

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
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
                    self.isCancelling = false
                    return
                }
                DispatchQueue.main.async {
                    self.delegate?.speechService(self, didFail: error)
                }
                self.stop()
            }
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
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
        
        guard status == noErr else { return }
        
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
        
        guard status == noErr else { return }
        
        for deviceID in devices {
            guard isInputDevice(deviceID: deviceID) else { continue }
            let deviceUID = getAudioDeviceUID(deviceID: deviceID)
            let deviceName = getAudioDeviceName(deviceID: deviceID)
            if deviceUID == "BuiltInMicrophoneDevice" || 
               deviceName.contains("MacBook Pro Microphone") ||
               deviceName.contains("Built-in Microphone") {
                setDefaultInputDevice(deviceID: deviceID)
                return
            }
        }
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
            print("Failed to set default input device: \(status)")
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
            print("Failed to get default input device: \(status)")
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
            return "Unknown Device (ID: \(deviceID))"
        }
        
        return deviceName as String
    }
    #endif
}


