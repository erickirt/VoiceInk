import Foundation

enum UserDefaultsKeys {
    // MARK: - Transcription Service
    enum TranscriptionService {
        static let transcriptionServiceType = "TranscriptionServiceType"
        static let cloudTranscriptionApiKey = "CloudTranscriptionApiKey"
        static let cloudTranscriptionApiEndpoint = "CloudTranscriptionApiEndpoint"
        static let cloudTranscriptionModelName = "CloudTranscriptionModelName"
        static let cloudTranscriptionLanguage = "CloudTranscriptionLanguage"
        static let selectedLanguage = "SelectedLanguage"
        static let transcriptionPrompt = "TranscriptionPrompt"
        static let currentModel = "CurrentModel"
    }
    
    // MARK: - Word Replacement
    enum WordReplacement {
        static let isEnabled = "IsWordReplacementEnabled"
        static let replacements = "wordReplacements"
    }
    
    // MARK: - Auto Copy
    enum AutoCopy {
        static let isEnabled = "IsAutoCopyEnabled"
    }
    
    // MARK: - Recorder
    enum Recorder {
        static let type = "RecorderType"
    }
    
    // MARK: - Ollama Service
    enum Ollama {
        static let baseURL = "ollamaBaseURL"
        static let selectedModel = "ollamaSelectedModel"
    }
    
    // MARK: - AI Enhancement
    enum AIEnhancement {
        static let isEnabled = "isAIEnhancementEnabled"
        static let useClipboardContext = "useClipboardContext"
        static let useScreenCaptureContext = "useScreenCaptureContext"
        static let assistantTriggerWord = "assistantTriggerWord"
        static let customPrompts = "customPrompts"
        static let selectedPromptId = "selectedPromptId"
    }
    
    // MARK: - Audio Device
    enum AudioDevice {
        static let inputMode = "audioInputMode"
        static let selectedDeviceID = "selectedAudioDeviceID"
        static let prioritizedDevices = "prioritizedDevices"
    }
    
    // MARK: - Dictionary
    enum Dictionary {
        static let data = "dictionary_data"
    }
    
    // MARK: - Menu Bar
    enum MenuBar {
        static let isMenuBarOnly = "IsMenuBarOnly"
    }
    
    // MARK: - Media Control
    enum Media {
        static let isPauseEnabled = "isMediaPauseEnabled"
    }
    
    // MARK: - Power Mode
    enum PowerMode {
        static let isEnabled = "PowerModeEnabled"
        static let defaultConfig = "PowerModeDefaultConfig"
        static let config = "PowerModeConfig"
    }
    
    // MARK: - Push To Talk
    enum PushToTalk {
        static let isEnabled = "isPushToTalkEnabled"
        static let key = "pushToTalkKey"
    }
    
    // MARK: - Audio Cleanup
    enum AudioCleanup {
        static let retentionPeriod = "AudioRetentionPeriod"
        static let isEnabled = "IsAudioCleanupEnabled"
    }
    
    // MARK: - Paste Method
    enum Paste {
        static let useAppleScriptPaste = "UseAppleScriptPaste"
    }
    
    // MARK: - Custom Provider
    enum CustomProvider {
        static let baseURL = "customProviderBaseURL"
        static let model = "customProviderModel"
    }
    
    // MARK: - License
    enum License {
        static let key = "VoiceInkLicense"
        static let trialStartDate = "VoiceInkTrialStartDate"
        static let activationId = "VoiceInkActivationId"
        static let aiProviderApiKey = "VoiceInkAIProviderKey"
    }
    
    // MARK: - Whisper Prompts
    enum WhisperPrompts {
        static let savedPrompts = "WhisperPrompts"
    }
}

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
    
    // MARK: - Word Replacement
    var isWordReplacementEnabled: Bool {
        get { bool(forKey: UserDefaultsKeys.WordReplacement.isEnabled) }
        set { set(newValue, forKey: UserDefaultsKeys.WordReplacement.isEnabled) }
    }
    
    // MARK: - Transcription Service
    var transcriptionServiceType: TranscriptionServiceType {
        get {
            if let rawValue = string(forKey: UserDefaultsKeys.TranscriptionService.transcriptionServiceType),
               let type = TranscriptionServiceType(rawValue: rawValue)
            {
                return type
            }
            return .local // Default to local if not set
        }
        set {
            set(newValue.rawValue, forKey: UserDefaultsKeys.TranscriptionService.transcriptionServiceType)
        }
    }
    
    var cloudTranscriptionApiKey: String {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionApiKey) ?? "" }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionApiKey) }
    }
    
    var cloudTranscriptionApiEndpoint: String {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionApiEndpoint) ?? "https://api.openai.com/v1/audio/transcriptions" }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionApiEndpoint) }
    }
    
    var cloudTranscriptionModelName: String {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionModelName) ?? "gpt-4o-transcribe" }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionModelName) }
    }
    
    var cloudTranscriptionLanguage: String? {
        get { string(forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionLanguage) }
        set { set(newValue, forKey: UserDefaultsKeys.TranscriptionService.cloudTranscriptionLanguage) }
    }
    
    // MARK: - License
    var aiProviderApiKey: String? {
        get { string(forKey: UserDefaultsKeys.License.aiProviderApiKey) }
        set { setValue(newValue, forKey: UserDefaultsKeys.License.aiProviderApiKey) }
    }
    
    var licenseKey: String? {
        get { string(forKey: UserDefaultsKeys.License.key) }
        set { setValue(newValue, forKey: UserDefaultsKeys.License.key) }
    }
    
    var trialStartDate: Date? {
        get { object(forKey: UserDefaultsKeys.License.trialStartDate) as? Date }
        set { setValue(newValue, forKey: UserDefaultsKeys.License.trialStartDate) }
    }
    
    var activationId: String? {
        get { string(forKey: UserDefaultsKeys.License.activationId) }
        set { setValue(newValue, forKey: UserDefaultsKeys.License.activationId) }
    }
}
