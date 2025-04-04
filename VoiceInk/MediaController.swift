import AppKit
import Combine
import Foundation
import os
import SwiftUI
import CoreAudio
import AudioToolbox

/// Controls system audio management during recording
class MediaController: ObservableObject {
    static let shared = MediaController()
    private var previousVolume: Float = 1.0
    private var didMuteAudio = false
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MediaController")
    
    @Published var isSystemMuteEnabled: Bool = UserDefaults.standard.isSystemMuteEnabled {
        didSet {
            UserDefaults.standard.isSystemMuteEnabled = isSystemMuteEnabled
        }
    }
    
    private init() {
        // Set default if not already set
        if !UserDefaults.standard.contains(key: UserDefaultsKeys.Media.isMuteEnabled) {
            UserDefaults.standard.isSystemMuteEnabled = true
        }
    }
    
    /// Mutes system audio during recording
    func muteSystemAudio() async -> Bool {
        guard isSystemMuteEnabled else {
            logger.info("System mute feature is disabled")
            return false
        }
        
        // Get current volume before muting
        previousVolume = getSystemVolume()
        logger.info("Muting system audio. Previous volume: \(self.previousVolume)")
        
        // Set system volume to 0 (mute)
        setSystemVolume(0.0)
        didMuteAudio = true
        return true
    }
    
    /// Restores system audio after recording
    func unmuteSystemAudio() async {
        guard isSystemMuteEnabled, didMuteAudio else {
            return
        }
        
        logger.info("Unmuting system audio to previous volume: \(self.previousVolume)")
        setSystemVolume(previousVolume)
        didMuteAudio = false
    }
    
    /// Gets the current system output volume (0.0 to 1.0)
    private func getSystemVolume() -> Float {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        
        // Get the default output device
        var getDefaultOutputDeviceProperty = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &getDefaultOutputDeviceProperty,
            0,
            nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID)
        
        if status != kAudioHardwareNoError {
            logger.error("Failed to get default output device: \(status)")
            return 1.0 // Default to full volume on error
        }
        
        // Get the volume
        var volume: Float = 0.0
        var volumeSize = UInt32(MemoryLayout.size(ofValue: volume))
        
        var volumeProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        
        let volumeStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &volumeProperty,
            0,
            nil,
            &volumeSize,
            &volume)
        
        if volumeStatus != kAudioHardwareNoError {
            logger.error("Failed to get system volume: \(volumeStatus)")
            return 1.0 // Default to full volume on error
        }
        
        return volume
    }
    
    /// Sets the system output volume (0.0 to 1.0)
    private func setSystemVolume(_ volume: Float) {
        var defaultOutputDeviceID = AudioDeviceID(0)
        var defaultOutputDeviceIDSize = UInt32(MemoryLayout.size(ofValue: defaultOutputDeviceID))
        
        // Get the default output device
        var getDefaultOutputDeviceProperty = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &getDefaultOutputDeviceProperty,
            0,
            nil,
            &defaultOutputDeviceIDSize,
            &defaultOutputDeviceID)
        
        if status != kAudioHardwareNoError {
            logger.error("Failed to get default output device: \(status)")
            return
        }
        
        // Clamp volume to valid range
        var safeVolume = max(0.0, min(1.0, volume))
        
        // Set the volume
        var volumeProperty = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        
        let volumeStatus = AudioObjectSetPropertyData(
            defaultOutputDeviceID,
            &volumeProperty,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: safeVolume)),
            &safeVolume)
        
        if volumeStatus != kAudioHardwareNoError {
            logger.error("Failed to set system volume: \(volumeStatus)")
        } else {
            logger.info("Set system volume to \(safeVolume)")
        }
    }
}
