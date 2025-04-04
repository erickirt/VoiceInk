import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor // Change to MainActor since we need to interact with UI
class Recorder: ObservableObject {
    private var recorder: AVAudioRecorder?
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private var deviceObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let mediaController = MediaController.shared
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    private var levelMonitorTimer: Timer?
    
    enum RecorderError: Error {
        case couldNotStartRecording
        case deviceConfigurationFailed
    }
    
    init() {
        logger.info("Initializing Recorder")
        setupDeviceChangeObserver()
    }
    
    private func setupDeviceChangeObserver() {
        logger.info("Setting up device change observer")
        deviceObserver = AudioDeviceConfiguration.createDeviceChangeObserver { [weak self] in
            Task {
                await self?.handleDeviceChange()
            }
        }
    }
    
    private func handleDeviceChange() async {
        guard !isReconfiguring else {
            logger.warning("Device change already in progress, skipping")
            return
        }
        
        logger.info("Handling device change")
        isReconfiguring = true
        
        // If we're recording, we need to stop and restart with new device
        if recorder != nil {
            logger.info("Active recording detected during device change")
            let currentURL = recorder?.url
            let currentDelegate = recorder?.delegate
            
            stopRecording()
            
            // Wait briefly for the device change to take effect
            logger.info("Waiting for device change to take effect")
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            if let url = currentURL {
                do {
                    logger.info("Attempting to restart recording with new device")
                    try await startRecording(toOutputFile: url, delegate: currentDelegate)
                    logger.info("Successfully reconfigured recording with new device")
                } catch {
                    logger.error("Failed to restart recording after device change: \(error.localizedDescription)")
                }
            }
        }
        
        isReconfiguring = false
        logger.info("Device change handling completed")
    }
    
    private func configureAudioSession(with deviceID: AudioDeviceID) async throws {
        logger.info("Starting audio session configuration for device ID: \(deviceID)")
        
        // Add a small delay to ensure device is ready after system changes
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        do {
            // Get the audio format from the selected device
            let format = try AudioDeviceConfiguration.configureAudioSession(with: deviceID)
            logger.info("Got audio format - Sample rate: \(format.mSampleRate), Channels: \(format.mChannelsPerFrame)")
            
            // Configure the device for recording
            try AudioDeviceConfiguration.setDefaultInputDevice(deviceID)
            logger.info("Successfully set default input device")
        } catch {
            logger.error("Audio session configuration failed: \(error.localizedDescription)")
            logger.error("Device ID: \(deviceID)")
            if let deviceName = deviceManager.getDeviceName(deviceID: deviceID) {
                logger.error("Failed device name: \(deviceName)")
            }
            throw error
        }
        
        // Add another small delay to allow configuration to settle
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        if let deviceName = deviceManager.getDeviceName(deviceID: deviceID) {
            logger.info("Successfully configured recorder with device: \(deviceName) (ID: \(deviceID))")
        }
    }
    
    func startRecording(toOutputFile url: URL, delegate: AVAudioRecorderDelegate?) async throws {
        logger.info("Starting recording process")
        
        // Check if we need to mute system audio
        let wasMuted = await mediaController.muteSystemAudio()
        if wasMuted {
            logger.info("System audio muted for recording")
        }
        
        // Get the current selected device
        let deviceID = deviceManager.getCurrentDevice()
        if deviceID != 0 {
            do {
                logger.info("Configuring audio session with device ID: \(deviceID)")
                if let deviceName = deviceManager.getDeviceName(deviceID: deviceID) {
                    logger.info("Attempting to configure device: \(deviceName)")
                }
                try await configureAudioSession(with: deviceID)
                logger.info("Successfully configured audio session")
            } catch {
                logger.error("Failed to configure audio device: \(error.localizedDescription), Device ID: \(deviceID)")
                if let deviceName = deviceManager.getDeviceName(deviceID: deviceID) {
                    logger.error("Failed device name: \(deviceName)")
                }
                logger.info("Falling back to default device")
            }
        } else {
            logger.info("Using default audio device (no custom device selected)")
        }
        
        logger.info("Setting up recording with settings: 16000Hz, 1 channel, PCM format")
        let recordSettings: [String : Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            logger.info("Initializing AVAudioRecorder with URL: \(url.path)")
            let recorder = try AVAudioRecorder(url: url, settings: recordSettings)
            recorder.delegate = delegate
            recorder.isMeteringEnabled = true // Enable metering
            
            logger.info("Attempting to start recording...")
            if recorder.record() {
                logger.info("Recording started successfully")
                self.recorder = recorder
                startLevelMonitoring()
            } else {
                logger.error("Failed to start recording - recorder.record() returned false")
                logger.error("Current device ID: \(deviceID)")
                if let deviceName = deviceManager.getDeviceName(deviceID: deviceID) {
                    logger.error("Current device name: \(deviceName)")
                }
                
                // Restore system audio if we muted it but failed to start recording
                await mediaController.unmuteSystemAudio()
                
                throw RecorderError.couldNotStartRecording
            }
        } catch {
            logger.error("Error creating AVAudioRecorder: \(error.localizedDescription)")
            logger.error("Recording settings used: \(recordSettings)")
            logger.error("Output URL: \(url.path)")
            
            // Restore system audio if we muted it but failed to start recording
            await mediaController.unmuteSystemAudio()
            
            throw error
        }
    }
    
    func stopRecording() {
        logger.info("Stopping recording")
        stopLevelMonitoring()
        recorder?.stop()
        recorder?.delegate = nil // Remove delegate
        recorder = nil
        
        // Force a device change notification to trigger system audio profile reset
        logger.info("Triggering audio device change notification")
        NotificationCenter.default.post(name: NSNotification.Name("AudioDeviceChanged"), object: nil)
        
        // Restore system audio if we muted it
        Task {
            await mediaController.unmuteSystemAudio()
        }
        
        logger.info("Recording stopped successfully")
    }
    
    private func startLevelMonitoring() {
        levelMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateAudioLevel()
        }
    }
    
    private func stopLevelMonitoring() {
        levelMonitorTimer?.invalidate()
        levelMonitorTimer = nil
        audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    }
    
    private func updateAudioLevel() {
        guard let recorder = recorder else { return }
        recorder.updateMeters()
        
        // Get the power values in decibels
        let averagePowerDb = recorder.averagePower(forChannel: 0)
        let peakPowerDb = recorder.peakPower(forChannel: 0)
        
        // Convert from dB to linear scale using proper conversion
        let normalizedAverage = pow(10, Double(averagePowerDb) / 30)
        let normalizedPeak = pow(10, Double(peakPowerDb) / 30)
        
        // Apply standard scaling factor for all devices
        let scalingFactor = 2.5
        
        // Update the audio meter with scaled values
        let scaledAverage = min(normalizedAverage * scalingFactor, 1.0)
        let scaledPeak = min(normalizedPeak * scalingFactor, 1.0)
        
        audioMeter = AudioMeter(
            averagePower: scaledAverage,
            peakPower: scaledPeak
        )
    }
    
    deinit {
        logger.info("Deinitializing Recorder")
        if let observer = deviceObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        Task { @MainActor in
            stopLevelMonitoring()
        }
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}
