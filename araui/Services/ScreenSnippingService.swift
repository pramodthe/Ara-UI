//
//  ScreenSnippingService.swift
//  araui
//
//  Screen snipping service to capture screen regions
//

import Foundation
import AppKit
import Carbon

final class ScreenSnippingService {
    static let shared = ScreenSnippingService()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    private init() {}
    
    func startMonitoring() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                // Check for Option+C (keyCode 8 is 'c')
                if keyCode == 8 && flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
                    DispatchQueue.main.async {
                        ScreenSnippingService.shared.captureScreenSnip()
                    }
                    return nil // Consume the event
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: nil
        ) else {
            print("Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        self.runLoopSource = runLoopSource
    }
    
    func stopMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
    }
    
    private func captureScreenSnip() {
        // Use screencapture command to get interactive selection
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        
        // Get the workspace directory
        let workspaceURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/AraUI")
        try? FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let clipPath = workspaceURL.appendingPathComponent("clip.png").path
        
        // -i for interactive selection, -s for no sound
        task.arguments = ["-i", "-s", clipPath]
        
        do {
            try task.run()
        } catch {
            print("Failed to capture screen: \(error)")
        }
    }
}
