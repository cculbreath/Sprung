import Foundation

struct DescriptorValueValidator {
    struct ValidationResult {
        let isValid: Bool
        let messages: [String]

        static let valid = ValidationResult(isValid: true, messages: [])

        func merging(_ other: ValidationResult) -> ValidationResult {
            ValidationResult(
                isValid: isValid && other.isValid,
                messages: messages + other.messages
            )
        }
    }

    func validate(
        _ value: Any?,
        descriptor: TemplateManifest.Section.FieldDescriptor
    ) -> ValidationResult {
        if descriptor.repeatable {
            guard let array = value as? [Any], array.isEmpty == false else {
                if descriptor.required {
                    let message = descriptor.validation?.message ?? "At least one value is required."
                    return ValidationResult(isValid: false, messages: [message])
                }
                return .valid
            }

            if let childDescriptor = descriptor.children?.first {
                return array.reduce(.valid) { partial, element in
                    partial.merging(validate(element, descriptor: childDescriptor))
                }
            } else {
                return array.reduce(.valid) { partial, element in
                    let string = stringValue(from: element) ?? ""
                    return partial.merging(evaluateLeafValue(string, descriptor: descriptor))
                }
            }
        }

        if let children = descriptor.children, children.isEmpty == false {
            guard let dict = value as? [String: Any] else {
                if descriptor.required {
                    let message = descriptor.validation?.message ?? "Missing required values."
                    return ValidationResult(isValid: false, messages: [message])
                }
                return .valid
            }

            return children.reduce(.valid) { partial, childDescriptor in
                let childValue = dict[childDescriptor.key]
                return partial.merging(validate(childValue, descriptor: childDescriptor))
            }
        }

        let string = stringValue(from: value) ?? ""
        return evaluateLeafValue(string, descriptor: descriptor)
    }

    private func stringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        case let dict as [String: Any]:
            return dict["value"] as? String
        default:
            return nil
        }
    }

    private func evaluateLeafValue(
        _ value: String,
        descriptor: TemplateManifest.Section.FieldDescriptor
    ) -> ValidationResult {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if descriptor.required && trimmed.isEmpty {
            let message = descriptor.validation?.message ?? "This field is required."
            return ValidationResult(isValid: false, messages: [message])
        }

        guard let validation = descriptor.validation, trimmed.isEmpty == false else {
            return .valid
        }

        let message = validation.message ?? defaultMessage(for: validation.rule)
        switch validation.rule {
        case .regex:
            if let pattern = validation.pattern,
               let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .email:
            let pattern = validation.pattern ?? "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .url:
            guard let url = URL(string: trimmed), url.scheme != nil else {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .phone:
            let pattern = validation.pattern ?? "^[0-9+()\\-\\s]{7,}$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) == nil {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .minLength:
            if let min = validation.min, Double(trimmed.count) < min {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .maxLength:
            if let max = validation.max, Double(trimmed.count) > max {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .lengthRange:
            if let min = validation.min, Double(trimmed.count) < min {
                return ValidationResult(isValid: false, messages: [message])
            }
            if let max = validation.max, Double(trimmed.count) > max {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .enumeration:
            let options = validation.options ?? []
            if options.isEmpty == false &&
                options.contains(where: { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) == false {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .numericRange:
            guard let number = Double(trimmed) else {
                return ValidationResult(isValid: false, messages: [message])
            }
            if let min = validation.min, number < min {
                return ValidationResult(isValid: false, messages: [message])
            }
            if let max = validation.max, number > max {
                return ValidationResult(isValid: false, messages: [message])
            }
        case .custom:
            break
        }

        return .valid
    }

    private func defaultMessage(
        for rule: TemplateManifest.Section.FieldDescriptor.Validation.Rule
    ) -> String {
        switch rule {
        case .regex, .custom:
            return "Value does not match the expected format."
        case .email:
            return "Enter a valid email address."
        case .url:
            return "Enter a valid URL."
        case .phone:
            return "Enter a valid phone number."
        case .minLength:
            return "Value is too short."
        case .maxLength:
            return "Value is too long."
        case .lengthRange:
            return "Value is not within the allowed length."
        case .enumeration:
            return "Value must match one of the allowed options."
        case .numericRange:
            return "Value is outside the allowed range."
        }
    }
}
