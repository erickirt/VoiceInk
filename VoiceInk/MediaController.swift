import AppKit
import Combine
import Foundation
import os
import SwiftUI

/// Controls media playback management during recording
class MediaController: ObservableObject {
    static let shared = MediaController()
    private var mediaRemoteHandle: UnsafeMutableRawPointer?
    private var didAttemptPauseMedia = false
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MediaController")
    
    @Published var isMediaPauseEnabled: Bool = UserDefaults.standard.isMediaPauseEnabled {
        didSet {
            UserDefaults.standard.isMediaPauseEnabled = isMediaPauseEnabled
        }
    }
    
    // Additional function pointers for direct control
    private var mrSendCommand: (@convention(c) (Int, [String: Any]?) -> Bool)?
    
    // MediaRemote command constants
    private let kMRPlay = 0
    private let kMRPause = 1
    
    private init() {
        // Set default if not already set
        if !UserDefaults.standard.contains(key: UserDefaultsKeys.Media.isPauseEnabled) {
            UserDefaults.standard.isMediaPauseEnabled = true
        }
        setupMediaRemote()
    }
    
    private func setupMediaRemote() {
        // Open the private framework
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            logger.error("Unable to open MediaRemote framework")
            return
        }
        mediaRemoteHandle = handle
        
        // Get the send command function pointer
        if let sendCommandPtr = dlsym(handle, "MRMediaRemoteSendCommand") {
            mrSendCommand = unsafeBitCast(sendCommandPtr, to: (@convention(c) (Int, [String: Any]?) -> Bool).self)
            logger.info("Successfully loaded MRMediaRemoteSendCommand function")
        } else {
            logger.warning("Could not find MRMediaRemoteSendCommand function, fallback to key simulation")
        }
        
        logger.info("MediaRemote framework initialized successfully")
    }
    
    deinit {
        if let handle = mediaRemoteHandle {
            dlclose(handle)
        }
    }
    
    /// Attempts to pause any potentially playing media
    func pauseMediaIfPlaying() async -> Bool {
        guard isMediaPauseEnabled else {
            logger.info("Media pause feature is disabled")
            return false
        }
        
        logger.info("Attempting to pause any potentially playing media")
        await MainActor.run {
            // Try direct command first, then fall back to key simulation
            if !sendMediaCommand(command: kMRPause) {
                sendMediaKey()
            }
        }
        didAttemptPauseMedia = true
        return true
    }
    
    /// Resumes media if it was paused by this controller
    func resumeMediaIfPaused() async {
        guard isMediaPauseEnabled, didAttemptPauseMedia else {
            return
        }
        
        logger.info("Resuming potentially paused media")
        await MainActor.run {
            // Try direct command first, then fall back to key simulation
            if !sendMediaCommand(command: kMRPlay) {
                sendMediaKey()
            }
        }
        didAttemptPauseMedia = false
    }
    
    /// Sends a media command using the MediaRemote framework
    private func sendMediaCommand(command: Int) -> Bool {
        guard let sendCommand = mrSendCommand else {
            logger.warning("MRMediaRemoteSendCommand not available")
            return false
        }
        
        let result = sendCommand(command, nil)
        logger.info("Sent media command \(command) with result: \(result)")
        return result
    }
    
    /// Simulates a media key press (Play/Pause)
    private func sendMediaKey() {
        let NX_KEYTYPE_PLAY: UInt32 = 16
        let keys = [NX_KEYTYPE_PLAY]
        
        logger.info("Simulating media key press using NSEvent")
        
        for key in keys {
            func postKeyEvent(down: Bool) {
                let flags: NSEvent.ModifierFlags = down ? .init(rawValue: 0xA00) : .init(rawValue: 0xB00)
                let data1 = Int((key << 16) | (down ? 0xA << 8 : 0xB << 8))
                
                if let event = NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: flags,
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,
                    data1: data1,
                    data2: -1
                ) {
                    // Attempt to post directly to all applications
                    let didPost = event.cgEvent?.post(tap: .cghidEventTap) != nil
                    logger.info("Posted key event (down: \(down)) with result: \(didPost ? "success" : "failure")")
                    
                    // Add a small delay to ensure the event is processed
                    usleep(10000) // 10ms delay
                }
            }
            
            // Perform the key down/up sequence
            postKeyEvent(down: true)
            postKeyEvent(down: false)
            
            // Allow some time for the system to process the key event
            usleep(50000) // 50ms delay
        }
        
        // As a fallback, try to use CGEvent directly
        createAndPostPlayPauseEvent()
    }
    
    /// Creates and posts a CGEvent for media control as a fallback method
    private func createAndPostPlayPauseEvent() {
        logger.info("Attempting fallback CGEvent for media control")
        
        // Media keys as defined in IOKit
        let NX_KEYTYPE_PLAY: Int64 = 16
        
        // Create a CGEvent for the media key
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            logger.error("Failed to create CGEventSource")
            return
        }
        
        if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: UInt16(NX_KEYTYPE_PLAY), keyDown: true) {
            keyDownEvent.flags = .init(rawValue: 0xA00)
            keyDownEvent.post(tap: .cghidEventTap)
            logger.info("Posted play/pause key down event")
            
            // Small delay between down and up events
            usleep(10000) // 10ms
            
            if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: UInt16(NX_KEYTYPE_PLAY), keyDown: false) {
                keyUpEvent.flags = .init(rawValue: 0xB00)
                keyUpEvent.post(tap: .cghidEventTap)
                logger.info("Posted play/pause key up event")
            }
        }
    }
}
