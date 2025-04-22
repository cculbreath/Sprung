import Foundation

/// Specifies which OpenAI client implementation to use
enum OpenAIClientType {
    /// Use SwiftOpenAI implementation
    case swiftOpenAI
    /// Use MacPaw/OpenAI implementation
    case macPawOpenAI
}

/// Factory for creating OpenAI clients
class OpenAIClientFactory {
    /// Default client type to use - MacPaw/OpenAI for TTS support
    static var defaultType: OpenAIClientType = .macPawOpenAI

    /// Creates an OpenAI client with the given API key
    /// - Parameters:
    ///   - apiKey: The API key to use for requests
    ///   - type: The type of client to create (default is defaultType)
    /// - Returns: An instance conforming to OpenAIClientProtocol
    static func createClient(apiKey: String, type: OpenAIClientType? = nil) -> OpenAIClientProtocol {
        let clientType = type ?? defaultType

        switch clientType {
        case .swiftOpenAI:
            return SwiftOpenAIClient(apiKey: apiKey)
        case .macPawOpenAI:
            return MacPawOpenAIClient(apiKey: apiKey)
        }
    }
    
    /// Creates a TTS-capable client
    /// - Parameter apiKey: The API key to use for requests
    /// - Returns: An OpenAIClientProtocol that supports TTS
    static func createTTSClient(apiKey: String) -> OpenAIClientProtocol {
        // MacPaw/OpenAI is required for TTS
        return MacPawOpenAIClient(apiKey: apiKey)
    }
}
