import Foundation
import SwiftyJSON

enum SchemaValidator {
    struct ValidationResult {
        let errors: [String]
    }

    static func validateApplicantProfile(_ json: JSON) -> ValidationResult {
        var errors: [String] = []
        let requiredKeys: Set<String> = ["name", "email", "phone", "city", "state"]

        for key in requiredKeys {
            let value = json[key]
            if value.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                errors.append("ApplicantProfile missing \(key)")
            }
        }

        return ValidationResult(errors: errors)
    }

    static func validateDefaultValues(_ json: JSON) -> ValidationResult {
        var errors: [String] = []

        let education = json["education"].arrayValue
        if education.isEmpty {
            errors.append("DefaultValues requires at least one education entry")
        }
        for (index, entry) in education.enumerated() {
            if entry["degree"].string?.isEmpty ?? true {
                errors.append("Education[\(index)].degree is required")
            }
            if entry["institution"].string?.isEmpty ?? true {
                errors.append("Education[\(index)].institution is required")
            }
        }

        let employment = json["employment"].arrayValue
        if employment.isEmpty {
            errors.append("DefaultValues requires at least one employment entry")
        }
        for (index, job) in employment.enumerated() {
            if job["company"].string?.isEmpty ?? true {
                errors.append("Employment[\(index)].company is required")
            }
            if job["title"].string?.isEmpty ?? true {
                errors.append("Employment[\(index)].title is required")
            }
        }

        return ValidationResult(errors: errors)
    }

    static func validateFactLedger(_ entries: [JSON]) -> ValidationResult {
        var errors: [String] = []

        for (index, entry) in entries.enumerated() where entry.type == .dictionary {
            let title = entry["title"].string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if title.isEmpty {
                errors.append("FactLedger[\(index)] requires a title")
            }

            let value = entry["value"]
            let hasNonEmptyValue: Bool
            switch value.type {
            case .array:
                hasNonEmptyValue = !value.arrayValue.isEmpty
            case .string:
                hasNonEmptyValue = !(value.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            case .dictionary:
                hasNonEmptyValue = !(value.dictionaryObject?.isEmpty ?? true)
            case .number, .bool:
                hasNonEmptyValue = true
            default:
                hasNonEmptyValue = false
            }
            if !hasNonEmptyValue {
                errors.append("FactLedger[\(index)] requires a non-empty value")
            }

            if let evidenceEntries = value.array {
                for (evidenceIndex, evidence) in evidenceEntries.enumerated() {
                    if evidence["title"].string?.isEmpty ?? true {
                        errors.append("FactLedger[\(index)].value[\(evidenceIndex)] requires title")
                    }
                    if evidence["value"].type == .null && evidence["summary"].type == .null {
                        errors.append("FactLedger[\(index)].value[\(evidenceIndex)] requires summary/value content")
                    }
                }
            }
        }

        return ValidationResult(errors: errors)
    }

    static func validateStyleProfile(_ json: JSON) -> ValidationResult {
        var errors: [String] = []

        let styleVector = json["style_vector"]
        if styleVector.type != .dictionary {
            errors.append("StyleProfile requires style_vector object")
        } else {
            let requiredMetrics = [
                "tone",
                "avg_sentence_len",
                "active_voice_ratio",
                "quant_density_per_100w"
            ]
            for metric in requiredMetrics {
                if styleVector[metric].type == .null {
                    errors.append("StyleProfile.style_vector missing \(metric)")
                }
            }
        }

        let samples = json["samples"].arrayValue
        if samples.isEmpty {
            errors.append("StyleProfile requires at least one writing sample reference")
        }
        for (index, sample) in samples.enumerated() {
            if sample["sample_id"].string?.isEmpty ?? true {
                errors.append("StyleProfile.samples[\(index)] missing sample_id")
            }
            if sample["type"].string?.isEmpty ?? true {
                errors.append("StyleProfile.samples[\(index)] missing type")
            }
        }

        return ValidationResult(errors: errors)
    }

    static func validateWritingSamples(_ samples: [JSON]) -> ValidationResult {
        var errors: [String] = []

        for (index, sample) in samples.enumerated() {
            if sample["sample_id"].string?.isEmpty ?? true && sample["id"].string?.isEmpty ?? true {
                errors.append("WritingSamples[\(index)] missing identifier")
            }
            if sample["title"].string?.isEmpty ?? true && sample["name"].string?.isEmpty ?? true {
                errors.append("WritingSamples[\(index)] requires title or name")
            }
        }

        return ValidationResult(errors: errors)
    }
}
