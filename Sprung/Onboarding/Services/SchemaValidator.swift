import Foundation
import SwiftyJSON

enum SchemaValidator {
    struct ValidationResult {
        let errors: [String]
        let warnings: [String]

        var isValid: Bool { errors.isEmpty }
    }

    static func validateApplicantProfile(_ json: JSON) -> ValidationResult {
        var errors: [String] = []
        let required = ["name", "email", "phone", "city", "state"]
        for key in required where json[key].string?.isEmpty ?? true {
            errors.append("ApplicantProfile missing \(key)")
        }
        return ValidationResult(errors: errors, warnings: [])
    }

    static func validateDefaultValues(_ json: JSON) -> ValidationResult {
        var errors: [String] = []
        if json["education"].array?.isEmpty ?? true {
            errors.append("DefaultValues requires at least one education entry")
        }
        if json["employment"].array?.isEmpty ?? true {
            errors.append("DefaultValues requires at least one employment entry")
        }
        return ValidationResult(errors: errors, warnings: [])
    }
}
