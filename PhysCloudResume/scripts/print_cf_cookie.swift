// print_cf_cookie.swift
// ---------------------
// CLI helper: prints the `cf_clearance=<value>` cookie for a given URL’s
// domain, obtaining a fresh one via CloudflareCookieManager if needed.
//
// Build  (from repo root):
//   swiftc -framework WebKit \
//      PhysCloudResume/scripts/print_cf_cookie.swift \
//      PhysCloudResume/Models/UtilityClasses/CloudflareCookieManager.swift \
//      -o print_cf_cookie
//
// Example usage:
//   CLEAR=$(./print_cf_cookie https://www.indeed.com)
//   curl -A "$(defaults read com.apple.Safari CustomUserAgent)" \
//        -H "Cookie: $CLEAR" \
//        "https://www.indeed.com/viewjob?jk=..."

import Foundation
import WebKit

@main
@MainActor
struct PrintCFCookie {
    static func main() async {
        guard let raw = CommandLine.arguments.dropFirst().first,
              let url = URL(string: raw)
        else {
            fputs("Usage: print_cf_cookie <url>\n", stderr)
            exit(1)
        }

        if let cookie = await CloudflareCookieManager.clearance(for: url) {
            print("\(cookie.name)=\(cookie.value)")
        } else {
            fputs("Failed to obtain cf_clearance for \(url.host ?? raw)\n", stderr)
            exit(2)
        }
    }
}
