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
}
