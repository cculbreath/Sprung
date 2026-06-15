//
//  AnthropicDynamicValue+JSON.swift
//  Sprung
//
//  One JSON-encoding path for Anthropic tool_use input dictionaries, replacing
//  the `mapValues { $0.value }` + JSONSerialization idiom that was copy-pasted
//  with divergent fallbacks across the tool agents.
//

import Foundation
import SwiftOpenAI

extension Dictionary where Key == String, Value == AnthropicDynamicValue {
    /// The plain `[String: Any]` form, each value unwrapped for JSON serialization.
    var jsonObject: [String: Any] { mapValues { $0.value } }

    /// JSON-encoded tool input; `{}` if the values aren't a valid JSON object.
    var jsonData: Data {
        let object = jsonObject
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return Data("{}".utf8)
        }
        return data
    }

    /// JSON string form of `jsonData`.
    var jsonString: String { String(decoding: jsonData, as: UTF8.self) }
}
