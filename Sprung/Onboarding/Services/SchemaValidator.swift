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
        var warnings: [String] = []

        let allowedKeys: Set<String> = [
            "name",
            "address",
            "city",
            "state",
            "zip",
            "phone",
            "email",
            "website",
            "picture",
            "signature_image"
        ]
        let requiredKeys: Set<String> = ["name", "email", "phone", "city", "state"]

        for key in json.dictionaryValue.keys where !allowedKeys.contains(key) {
            warnings.append("ApplicantProfile contains unsupported key '\(key)'")
        }

        for key in requiredKeys {
            let value = json[key]
            if value.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                errors.append("ApplicantProfile missing \(key)")
            }
        }

        if let email = json["email"].string, !email.contains("@") {
            warnings.append("ApplicantProfile email may be invalid: \(email)")
        }
        if let phone = json["phone"].string,
           phone.trimmingCharacters(in: .whitespacesAndNewlines).count < 7 {
            warnings.append("ApplicantProfile phone number is unusually short")
        }

        return ValidationResult(errors: errors, warnings: warnings)
    }

    static func validateDefaultValues(_ json: JSON) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

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
            if job["start_date"].string?.isEmpty ?? true {
                warnings.append("Employment[\(index)].start_date is empty")
            }
        }

        let skills = json["skills"].arrayValue
        if !skills.isEmpty && skills.contains(where: { $0.string == nil }) {
            warnings.append("Skills array should contain only strings")
        }

        return ValidationResult(errors: errors, warnings: warnings)
    }
}
