import Foundation
import OrderedCollections

struct TemplateManifest: Decodable {
    struct Section: Decodable {
        enum Kind: String, Decodable {
            case string
            case array
            case object
            case mapOfStrings
            case objectOfObjects
            case arrayOfObjects
            case fontSizes
        }

        let type: Kind
        let defaultValue: JSONValue?

        func emptyValue() -> Any {
            switch type {
            case .string:
                return ""
            case .array, .arrayOfObjects:
                return [Any]()
            case .object, .objectOfObjects:
                return [String: Any]()
            case .mapOfStrings:
                return [String: String]()
            case .fontSizes:
                return [String: String]()
            }
        }

        func defaultContextValue() -> Any? {
            guard let value = defaultValue?.value else { return nil }
            switch type {
            case .mapOfStrings:
                if let dict = value as? [String: Any] {
                    var result: [String: String] = [:]
                    for (key, inner) in dict {
                        if let stringValue = inner as? String {
                            result[key] = stringValue
                        }
                    }
                    return result
                }
                return nil
            default:
                return TemplateManifest.normalize(value)
            }
        }
    }

    struct JSONValue: Decodable {
        let value: Any

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                value = NSNull()
            } else if let dict = try? container.decode([String: JSONValue].self) {
                value = dict.mapValues(\.value)
            } else if let array = try? container.decode([JSONValue].self) {
                value = array.map(\.value)
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
            } else if let int = try? container.decode(Int.self) {
                value = int
            } else if let double = try? container.decode(Double.self) {
                value = double
            } else {
                throw DecodingError.typeMismatch(
                    Any.self,
                    .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
                )
            }
        }
    }

    let slug: String
    let sectionOrder: [String]
    let sections: [String: Section]

    func section(for key: String) -> Section? {
        sections[key]
    }

    func makeDefaultContext() -> [String: Any] {
        var context: [String: Any] = [:]
        for key in sectionOrder {
            if let value = sections[key]?.defaultContextValue() {
                context[key] = value
            }
        }
        return context
    }

    static func normalize(_ value: Any) -> Any {
        switch value {
        case is NSNull:
            return NSNull()
        case let ordered as OrderedDictionary<String, Any>:
            var dict: [String: Any] = [:]
            for (key, inner) in ordered {
                dict[key] = normalize(inner)
            }
            return dict
        case let dict as [String: Any]:
            var normalized: [String: Any] = [:]
            for (key, inner) in dict {
                normalized[key] = normalize(inner)
            }
            return normalized
        case let array as [Any]:
            return array.map { normalize($0) }
        default:
            return value
        }
    }
}
