// ZoniApple - Apple platform extensions for Zoni
//
// AppleMLError.swift - Apple ML-specific error types

import Foundation

// MARK: - AppleMLError

/// Errors specific to Apple ML operations in ZoniApple.
///
/// These errors cover issues with on-device machine learning frameworks
/// including NaturalLanguage, Foundation Models, and MLX.
public enum AppleMLError: Error, Sendable {

    /// The requested ML model is not available on this device.
    ///
    /// - Parameters:
    ///   - name: The model name that was requested.
    ///   - reason: A description of why the model is unavailable.
    case modelNotAvailable(name: String, reason: String)

    /// The Apple ML framework is not available (OS version too old or not supported).
    ///
    /// - Parameters:
    ///   - framework: The framework name (e.g., "FoundationModels", "NaturalLanguage").
    ///   - minimumOS: The minimum OS version required.
    case frameworkNotAvailable(framework: String, minimumOS: String)

    /// The specified language is not supported for embeddings.
    ///
    /// - Parameter language: The language code that was requested.
    case languageNotSupported(language: String)

    /// Input text exceeds the model's maximum context length.
    ///
    /// - Parameters:
    ///   - length: The length of the input (tokens or characters).
    ///   - maximum: The maximum allowed length.
    case contextLengthExceeded(length: Int, maximum: Int)

    /// Memory allocation failed for the model.
    ///
    /// - Parameters:
    ///   - required: The memory required in bytes.
    ///   - available: The memory available in bytes (if known).
    case memoryAllocationFailed(required: Int, available: Int?)

    /// Neural Engine is not available on this device.
    case neuralEngineUnavailable

    /// Model download failed.
    ///
    /// - Parameters:
    ///   - model: The model identifier that failed to download.
    ///   - reason: A description of why the download failed.
    case modelDownloadFailed(model: String, reason: String)

    /// Tokenization of input text failed.
    ///
    /// - Parameter reason: A description of why tokenization failed.
    case tokenizationFailed(reason: String)

    /// Apple Intelligence is not enabled on this device.
    case appleIntelligenceNotEnabled

    /// The embedding operation produced invalid results.
    ///
    /// - Parameter reason: A description of what was invalid.
    case invalidEmbedding(reason: String)
}

// MARK: - LocalizedError

extension AppleMLError: LocalizedError {

    public var errorDescription: String? {
        switch self {
        case .modelNotAvailable(let name, let reason):
            return "Model '\(name)' is not available: \(reason)"

        case .frameworkNotAvailable(let framework, let minimumOS):
            return "\(framework) framework requires \(minimumOS) or later"

        case .languageNotSupported(let language):
            return "Language '\(language)' is not supported for embeddings"

        case .contextLengthExceeded(let length, let maximum):
            return "Input length (\(length)) exceeds maximum context length (\(maximum))"

        case .memoryAllocationFailed(let required, let available):
            if let available {
                return "Failed to allocate \(formatBytes(required)) (only \(formatBytes(available)) available)"
            }
            return "Failed to allocate \(formatBytes(required)) for model"

        case .neuralEngineUnavailable:
            return "Neural Engine is not available on this device"

        case .modelDownloadFailed(let model, let reason):
            return "Failed to download model '\(model)': \(reason)"

        case .tokenizationFailed(let reason):
            return "Tokenization failed: \(reason)"

        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled. Enable it in Settings > Apple Intelligence & Siri"

        case .invalidEmbedding(let reason):
            return "Invalid embedding result: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .modelNotAvailable:
            return "Try using a different model or check if the model needs to be downloaded first"

        case .frameworkNotAvailable(_, let minimumOS):
            return "Update your device to \(minimumOS) or later to use this feature"

        case .languageNotSupported:
            return "Use one of the supported languages. Call availableLanguages() to see the list"

        case .contextLengthExceeded(_, let maximum):
            return "Reduce the input text to under \(maximum) tokens or enable automatic truncation"

        case .memoryAllocationFailed:
            return "Close other applications to free up memory, or use a smaller model"

        case .neuralEngineUnavailable:
            return "Use CPU-only inference mode instead"

        case .modelDownloadFailed:
            return "Check your internet connection and try again"

        case .tokenizationFailed:
            return "Ensure the input text is valid UTF-8 and does not contain unsupported characters"

        case .appleIntelligenceNotEnabled:
            return "Go to Settings > Apple Intelligence & Siri and enable Apple Intelligence"

        case .invalidEmbedding:
            return "Try with different input text or use a different embedding provider"
        }
    }

    /// Formats bytes into a human-readable string.
    private func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}

// MARK: - CustomNSError

extension AppleMLError: CustomNSError {

    public static var errorDomain: String { "com.zoni.appleml" }

    public var errorCode: Int {
        switch self {
        case .modelNotAvailable: return 1001
        case .frameworkNotAvailable: return 1002
        case .languageNotSupported: return 1003
        case .contextLengthExceeded: return 1004
        case .memoryAllocationFailed: return 1005
        case .neuralEngineUnavailable: return 1006
        case .modelDownloadFailed: return 1007
        case .tokenizationFailed: return 1008
        case .appleIntelligenceNotEnabled: return 1009
        case .invalidEmbedding: return 1010
        }
    }

    public var errorUserInfo: [String: Any] {
        var info: [String: Any] = [:]

        if let description = errorDescription {
            info[NSLocalizedDescriptionKey] = description
        }
        if let suggestion = recoverySuggestion {
            info[NSLocalizedRecoverySuggestionErrorKey] = suggestion
        }

        return info
    }
}
