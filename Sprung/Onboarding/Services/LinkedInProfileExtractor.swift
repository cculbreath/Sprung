import Foundation
import SwiftSoup
import SwiftyJSON

enum LinkedInProfileExtractor {
    struct Result {
        let extraction: JSON
        let uncertainties: [String]
    }

    static func extract(from url: URL) async throws -> Result {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw ExtractionError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            throw ExtractionError.httpError(http.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ExtractionError.unreadableContent
        }

        return try parse(html: html, source: url.absoluteString)
    }

    static func parse(html: String, source: String) throws -> Result {
        let document = try SwiftSoup.parse(html)
        var extraction: [String: Any] = [:]
        var uncertainties: [String] = []

        if let nameElement = try document.select(".pv-text-details__left-panel h1").first() ?? document.select(".top-card-layout__title").first() {
            extraction["name"] = try nameElement.text()
        } else {
            uncertainties.append("name")
        }

        if let headline = try document.select(".pv-text-details__left-panel div~div").first() ?? document.select(".top-card-layout__headline").first() {
            extraction["headline"] = try headline.text()
        }

        if let location = try document.select(".pv-text-details__left-panel span.inline-block").first() ?? document.select(".top-card__subline-item").first() {
            extraction["location"] = try location.text()
        }

        if let summary = try document.select("section[data-section=\"summary\"] div.inline-show-more-text").first() {
            extraction["summary"] = try summary.text()
        }

        let experienceItems = try document.select("section[data-section=\"experience\"] li")
        if !experienceItems.isEmpty() {
            extraction["experience"] = try experienceItems.array().map { try $0.text() }
        }

        let educationItems = try document.select("section[data-section=\"education\"] li")
        if !educationItems.isEmpty() {
            extraction["education"] = try educationItems.array().map { try $0.text() }
        }

        extraction["source"] = source

        return Result(extraction: JSON(extraction), uncertainties: uncertainties)
    }

    enum ExtractionError: Error, LocalizedError {
        case invalidResponse
        case httpError(Int)
        case unreadableContent

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "LinkedIn request did not return an HTTP response"
            case .httpError(let status):
                return "LinkedIn request failed with status code \(status)"
            case .unreadableContent:
                return "LinkedIn profile content could not be decoded"
            }
        }
    }
}
