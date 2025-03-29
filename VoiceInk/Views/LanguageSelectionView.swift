import SwiftUI

// Define a display mode for flexible usage
enum LanguageDisplayMode {
    case full // For settings page with descriptions
    case menuItem // For menu bar with compact layout
}

struct LanguageSelectionView: View {
    @ObservedObject var whisperState: WhisperState
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "en"
    // Add display mode parameter with full as the default
    var displayMode: LanguageDisplayMode = .full

    private func updateLanguage(_ language: String) {
        // Update UI state - the UserDefaults updating is now automatic with @AppStorage
        selectedLanguage = language
    }
    
    // Function to check if current model is multilingual
    private func isMultilingualModel() -> Bool {
        guard let currentModel = whisperState.currentModel,
               let predefinedModel = PredefinedModels.models.first(where: { $0.name == currentModel.name }) else {
            return false
        }
        return predefinedModel.isMultilingualModel
    }

    // Function to get current model's supported languages
    private func getCurrentModelLanguages() -> [String: String] {
        guard let currentModel = whisperState.currentModel,
              let predefinedModel = PredefinedModels.models.first(where: {
                  $0.name == currentModel.name
              })
        else {
            return ["en": "English"] // Default to English if no model found
        }
        return predefinedModel.supportedLanguages
    }

    // Get the display name of the current language
    private func currentLanguageDisplayName() -> String {
        return getCurrentModelLanguages()[selectedLanguage] ?? "Unknown"
    }

    var body: some View {
        switch displayMode {
        case .full:
            fullView
        case .menuItem:
            menuItemView
        }
    }

    // The original full view layout for settings page
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Language")
                .font(.headline)

            if let currentModel = whisperState.currentModel,
               let predefinedModel = PredefinedModels.models.first(where: {
                   $0.name == currentModel.name
               })
            {
                if isMultilingualModel() {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Select Language", selection: $selectedLanguage) {
                            ForEach(
                                predefinedModel.supportedLanguages.sorted(by: {
                                    $0.value < $1.value
                                }), id: \.key
                            ) { key, value in
                                Text(value).tag(key)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .onChange(of: selectedLanguage) { newValue in
                            updateLanguage(newValue)
                        }

                        Text("Current model: \(predefinedModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(
                            "This model supports multiple languages. You can choose auto-detect or select a specific language."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                } else {
                    // For English-only models, force set language to English
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Language: English")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Text("Current model: \(predefinedModel.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(
                            "This is an English-optimized model and only supports English transcription."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .onAppear {
                        // Ensure English is set when viewing English-only model
                        updateLanguage("en")
                    }
                }
            } else {
                Text("No model selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // New compact view for menu bar
    private var menuItemView: some View {
        Group {
            if isMultilingualModel() {
                Menu {
                    ForEach(
                        getCurrentModelLanguages().sorted(by: { $0.value < $1.value }), id: \.key
                    ) { key, value in
                        Button {
                            updateLanguage(key)
                        } label: {
                            HStack {
                                Text(value)
                                if selectedLanguage == key {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Language: \(currentLanguageDisplayName())")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                    }
                }
            } else {
                // For English-only models
                Button {
                    // Do nothing, just showing info
                } label: {
                    Text("Language: English (only)")
                        .foregroundColor(.secondary)
                }
                .disabled(true)
                .onAppear {
                    // Ensure English is set for English-only models
                    updateLanguage("en")
                }
            }
        }
    }
}
