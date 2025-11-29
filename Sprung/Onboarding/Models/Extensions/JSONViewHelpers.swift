import Foundation
import SwiftyJSON

/// View helper extensions for cleaner JSON access in SwiftUI views.
/// These reduce verbose `json["field"].string` patterns to readable property access.
extension JSON {
    /// Returns the string value if non-empty, nil otherwise.
    /// Trims whitespace before checking emptiness.
    var nonEmptyString: String? {
        guard let value = self.string else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Display name with common fallbacks (name → title → "Unknown").
    var displayName: String {
        self["name"].nonEmptyString ?? self["title"].nonEmptyString ?? "Unknown"
    }

    /// Formatted city, region string (e.g., "San Francisco, CA").
    var formattedCityRegion: String? {
        let components = [self["city"].string, self["region"].string]
            .compactMap { $0?.nonEmptyTrimmed }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    /// Formatted full location from a location JSON object.
    /// Handles address, city, region, postalCode, countryCode fields.
    var formattedLocation: String? {
        guard self != .null else { return nil }
        var components: [String] = []

        if let address = self["address"].nonEmptyString {
            components.append(address)
        }

        let cityRegion = [self["city"].string, self["region"].string]
            .compactMap { $0?.nonEmptyTrimmed }
            .joined(separator: ", ")
        if !cityRegion.isEmpty {
            components.append(cityRegion)
        }

        if let postal = self["postalCode"].nonEmptyString {
            if components.isEmpty {
                components.append(postal)
            } else {
                components[components.count - 1] += " \(postal)"
            }
        }

        if let country = self["countryCode"].nonEmptyString {
            components.append(country)
        }

        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    /// Formatted date range string (e.g., "Jan 2020 - Present").
    var formattedDateRange: String? {
        guard let start = self["start"].nonEmptyString else { return nil }
        let end = self["end"].nonEmptyString ?? "Present"
        return "\(start) - \(end)"
    }

    /// URL string from common fields (url → website → link).
    var urlString: String? {
        self["url"].nonEmptyString ?? self["website"].nonEmptyString ?? self["link"].nonEmptyString
    }
}

// MARK: - String Helpers

private extension String {
    /// Returns nil if the string is empty after trimming whitespace.
    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
