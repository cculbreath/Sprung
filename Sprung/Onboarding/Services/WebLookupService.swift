import Foundation
import SwiftSoup
@preconcurrency import SwiftyJSON

enum WebLookupService {
    struct Result: @unchecked Sendable {
        let entries: [JSON]
        let notices: [String]
    }

    static func search(query: String) async throws -> Result {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://duckduckgo.com/html/?q=\(encodedQuery)") else {
            throw LookupError.invalidQuery
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LookupError.httpError
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw LookupError.unreadableContent
        }

        let document = try SwiftSoup.parse(html)
        let results = try document.select("div.result")
        var entries: [JSON] = []

        for element in results.array().prefix(5) {
            let title = try element.select("a.result__a").first()?.text() ?? ""
            let link = try element.select("a.result__a").first()?.attr("href") ?? ""
            let snippet = try element.select("a.result__snippet").first()?.text() ?? ""

            guard !title.isEmpty, !link.isEmpty else { continue }

            entries.append(JSON([
                "title": title,
                "link": link,
                "snippet": snippet
            ]))
        }

        return Result(entries: entries, notices: entries.isEmpty ? ["No public results retrieved"] : [])
    }

    enum LookupError: Error, LocalizedError {
        case invalidQuery
        case httpError
        case unreadableContent

        var errorDescription: String? {
            switch self {
            case .invalidQuery:
                return "Search query could not be encoded"
            case .httpError:
                return "Search request failed"
            case .unreadableContent:
                return "Search results could not be parsed"
            }
        }
    }
}
