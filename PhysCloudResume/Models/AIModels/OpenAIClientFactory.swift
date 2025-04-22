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
    /// Default client type to use
    static var defaultType: OpenAIClientType = .swiftOpenAI
    
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
}