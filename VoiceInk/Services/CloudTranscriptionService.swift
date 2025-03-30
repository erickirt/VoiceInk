//
//  CloudTranscriptionService.swift
//  VoiceInk
//
//  Created by Wing CHAN on 29/3/2025.
//

import Foundation
import os

/// Error types specific to cloud transcription
enum CloudTranscriptionError: Error {
    case authenticationFailed
    case networkError(Error)
    case invalidResponse
    case serviceUnavailable
    case rateLimitExceeded
    case unsupportedLanguage
    case invalidAudioFormat
    case configurationError
    case emptyApiKey
    case invalidEndpointURL
    case fileNotFound
}

/// A transcription service implementation that uses OpenAI's GPT-4o-transcribe model
actor CloudTranscriptionService: TranscriptionService {
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CloudTranscriptionService")
    private var apiKey: String
    private var apiEndpoint: URL
    private var model: String = "gpt-4o-transcribe"
    private var language: String?
    private var prompt: String?
    private var transcriptionResult: String = ""
    private let session: URLSession
    
    // Retry configuration
    private let maxRetryAttempts = 3
    private let retryDelay: TimeInterval = 1.0  // seconds
    private let useExponentialBackoff = true
    
    // MARK: - Initialization
    
    init(apiKey: String, apiEndpoint: String) throws {
        // Validate API key format
        guard !apiKey.isEmpty else {
            throw CloudTranscriptionError.emptyApiKey
        }
        
        // Validate endpoint URL
        guard let url = URL(string: apiEndpoint) else {
            throw CloudTranscriptionError.invalidEndpointURL
        }
        
        // Verify URL has at least http:// or https:// scheme
        guard url.scheme == "http" || url.scheme == "https" else {
            throw CloudTranscriptionError.invalidEndpointURL
        }
        
        self.apiKey = apiKey
        self.apiEndpoint = url
        self.session = URLSession.shared
        
        logger.notice("CloudTranscriptionService initialized with OpenAI endpoint: \(apiEndpoint)")
    }
    
    static func createService(configuration: [String: Any]) async throws -> CloudTranscriptionService {
        guard let apiKey = configuration["apiKey"] as? String else {
            throw CloudTranscriptionError.configurationError
        }
        
        // Default OpenAI endpoint if not provided
        let apiEndpoint = (configuration["apiEndpoint"] as? String) ?? "https://api.openai.com/v1/audio/transcriptions"
        
        // Validate API key is not empty
        guard !apiKey.isEmpty else {
            throw CloudTranscriptionError.emptyApiKey
        }
        
        // Validate endpoint format
        guard let _ = URL(string: apiEndpoint),
              apiEndpoint.hasPrefix("http://") || apiEndpoint.hasPrefix("https://") else {
            throw CloudTranscriptionError.invalidEndpointURL
        }
        
        let service = try CloudTranscriptionService(apiKey: apiKey, apiEndpoint: apiEndpoint)
        
        // Set model name if provided
        if let modelName = configuration["modelName"] as? String {
            await service.setModel(modelName)
        }
        
        return service
    }
    
    func fullTranscribeFromURL(fileURL: URL) async throws {
        // Validate API key is still valid at time of transcription
        guard !apiKey.isEmpty else {
            logger.error("❌ API key is empty")
            throw CloudTranscriptionError.emptyApiKey
        }
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.error("❌ Audio file not found at path: \(fileURL.path)")
            throw CloudTranscriptionError.fileNotFound
        }
        
        logger.notice("🔄 Starting OpenAI transcription from file URL using \(self.model)")
        
        // Initialize retry counter
        var retryCount = 0
        var lastError: Error? = nil
        
        // Retry loop
        repeat {
            do {
                try await performTranscriptionRequest(fileURL: fileURL)
                return // Success, exit function
            } catch let error as CloudTranscriptionError {
                lastError = error
                
                // Determine if this error is retryable
                let isRetryable = shouldRetry(error: error)
                
                if isRetryable && retryCount < maxRetryAttempts {
                    retryCount += 1
                    
                    // Calculate delay with exponential backoff and jitter if enabled
                    var delayTime = retryDelay * Double(retryCount)
                    if useExponentialBackoff {
                        delayTime = retryDelay * pow(2.0, Double(retryCount - 1))
                    }
                    
                    logger.notice("⏱️ Retrying transcription (attempt \(retryCount)/\(self.maxRetryAttempts)) after \(String(format: "%.2f", delayTime)) seconds. Error: \(error)")
                    
                    // Wait before retrying
                    try? await Task.sleep(nanoseconds: UInt64(delayTime * 1_000_000_000))
                    continue
                } else {
                    // Either not retryable or max retries reached
                    if !isRetryable {
                        logger.error("❌ Non-retryable error occurred: \(error.localizedDescription)")
                    } else {
                        logger.error("❌ Max retry attempts (\(self.maxRetryAttempts)) reached")
                    }
                    throw error
                }
            } catch {
                // Unknown error type
                lastError = error
                logger.error("❌ Unexpected error: \(error.localizedDescription)")
                throw CloudTranscriptionError.networkError(error)
            }
        } while retryCount < maxRetryAttempts
        
        // This should not be reached, but just in case
        if let error = lastError {
            throw error
        } else {
            throw CloudTranscriptionError.serviceUnavailable
        }
    }
    
    // Helper function to determine if an error is retryable
    private func shouldRetry(error: CloudTranscriptionError) -> Bool {
        switch error {
        case .networkError(_):
            return true
        case .serviceUnavailable, .rateLimitExceeded. .invalidResponse:
            // These are temporary errors that might resolve with a retry
            return true
        case .authenticationFailed, .unsupportedLanguage,
             .invalidAudioFormat, .configurationError, .emptyApiKey,
             .invalidEndpointURL, .fileNotFound:
            // These errors will likely not be resolved by retrying
            return false
        }
    }
    
    // Extracted actual API request logic to a separate function
    private func performTranscriptionRequest(fileURL: URL) async throws {
        // Prepare multipart form data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Read file data
        let audioData = try Data(contentsOf: fileURL)
        
        var formData = Data()
        
        // Add model parameter
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        formData.append("\(model)\r\n".data(using: .utf8)!)
        
        // Add file data
        formData.append("--\(boundary)\r\n".data(using: .utf8)!)
        formData.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        formData.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        formData.append(audioData)
        formData.append("\r\n".data(using: .utf8)!)
        
        // Add language parameter if not auto
        if let language = language, language.isEmpty == false, language.lowercased() != "auto" {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            formData.append("\(language)\r\n".data(using: .utf8)!)
        }
        
        // Add prompt if specified
        if let prompt = prompt {
            formData.append("--\(boundary)\r\n".data(using: .utf8)!)
            formData.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .utf8)!)
            formData.append("\(prompt)\r\n".data(using: .utf8)!)
        }
        
        // Close the form data
        formData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        // Set request body
        request.httpBody = formData
        
        // Send request to OpenAI service
        let (data, response) = try await session.data(for: request)
        
        // Check HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Invalid response format")
            throw CloudTranscriptionError.invalidResponse
        }
        
        // Handle HTTP status codes
        switch httpResponse.statusCode {
        case 200:
            // Parse successful response
            if let result = try? JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data) {
                self.transcriptionResult = result.text
                logger.notice("✅ OpenAI transcription successfully completed")
            } else if let text = String(data: data, encoding: .utf8) {
                // Fallback if response isn't JSON
                self.transcriptionResult = text
                logger.notice("✅ OpenAI transcription received plain text response")
            } else {
                logger.error("❌ Could not parse OpenAI response data")
                throw CloudTranscriptionError.invalidResponse
            }
        case 401:
            logger.error("❌ Authentication failed with OpenAI API key")
            throw CloudTranscriptionError.authenticationFailed
        case 429:
            logger.error("❌ OpenAI rate limit exceeded")
            throw CloudTranscriptionError.rateLimitExceeded
        case 400:
            if let errorData = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                logger.error("❌ OpenAI bad request: \(errorData.error.message)")
            } else {
                logger.error("❌ OpenAI bad request - possibly unsupported language or format")
            }
            throw CloudTranscriptionError.invalidAudioFormat
        case 500, 502, 503, 504:
            logger.error("❌ OpenAI service temporarily unavailable (status: \(httpResponse.statusCode))")
            throw CloudTranscriptionError.serviceUnavailable
        default:
            logger.error("❌ Unexpected HTTP status from OpenAI: \(httpResponse.statusCode)")
            throw CloudTranscriptionError.invalidResponse
        }
    }
    
    func getTranscription() -> String {
        return transcriptionResult
    }
    
    func setPrompt(_ prompt: String?) {
        self.prompt = prompt
        logger.debug("💬 Prompt set: \(prompt ?? "none")")
    }
    
    func setLanguage(_ language: String?) {
        self.language = language
        logger.debug("🌐 Language set: \(language ?? "none")")
    }
    
    func releaseResources() {
        // Clean up any resources if needed
        transcriptionResult = ""
        logger.debug("🧹 OpenAI transcription resources released")
    }
    
    func setModel(_ modelName: String) {
        self.model = modelName
        logger.debug("🤖 Model set: \(modelName)")
    }
}

// MARK: - Response Models

/// Model for parsing JSON response from the OpenAI transcription service
struct OpenAITranscriptionResponse: Decodable {
    let text: String
}

/// Model for parsing error responses from OpenAI
struct OpenAIErrorResponse: Decodable {
    struct ErrorDetail: Decodable {
        let message: String
        let type: String?
        let param: String?
        let code: String?
    }
    
    let error: ErrorDetail
}
