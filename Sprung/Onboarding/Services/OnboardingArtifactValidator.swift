import Foundation
import SwiftyJSON

struct OnboardingArtifactValidator {
    func issues(for artifacts: OnboardingArtifacts) -> [String] {
        var issues: [String] = []

        if let profile = artifacts.applicantProfile {
            let result = SchemaValidator.validateApplicantProfile(profile)
            issues.append(contentsOf: result.errors)
        }

        if let defaults = artifacts.defaultValues {
            let result = SchemaValidator.validateDefaultValues(defaults)
            issues.append(contentsOf: result.errors)
        }

        if !artifacts.factLedger.isEmpty {
            let result = SchemaValidator.validateFactLedger(artifacts.factLedger)
            issues.append(contentsOf: result.errors)
        }

        if let styleProfile = artifacts.styleProfile {
            let result = SchemaValidator.validateStyleProfile(styleProfile)
            issues.append(contentsOf: result.errors)
        }

        if !artifacts.writingSamples.isEmpty {
            let result = SchemaValidator.validateWritingSamples(artifacts.writingSamples)
            issues.append(contentsOf: result.errors)
        }

        return issues
    }

    func timelineConflicts(in defaultValues: JSON) -> [JSON] {
        let employment = defaultValues["employment"].arrayValue

        struct EmploymentInterval {
            let identifier: String
            let title: String
            let company: String
            let startDate: Date
            let startRaw: String
            let endDate: Date?
            let endRaw: String?
        }

        var intervals: [EmploymentInterval] = []

        for (index, job) in employment.enumerated() {
            let identifier = job["id"].string ?? "employment[\(index)]"
            let title = job["title"].string ?? "Role"
            let company = job["company"].string ?? "Company"
            let startRaw = job["start_date"].string ??
                job["start"].string ??
                job["timeline"]["start"].string ?? ""

            guard let startDate = parsePartialDate(from: startRaw) else { continue }

            let endRaw = job["end_date"].string ??
                job["end"].string ??
                job["timeline"]["end"].string
            let endDate = parsePartialDate(from: endRaw)

            let interval = EmploymentInterval(
                identifier: identifier,
                title: title,
                company: company,
                startDate: startDate,
                startRaw: startRaw,
                endDate: endDate,
                endRaw: endRaw
            )
            intervals.append(interval)
        }

        guard intervals.count > 1 else { return [] }

        var conflicts: [JSON] = []
        for i in 0..<(intervals.count - 1) {
            for j in (i + 1)..<intervals.count {
                let first = intervals[i]
                let second = intervals[j]

                let firstEnd = first.endDate ?? .distantFuture
                let secondEnd = second.endDate ?? .distantFuture

                let rangesOverlap = first.startDate <= secondEnd && second.startDate <= firstEnd
                guard rangesOverlap else { continue }

                let entryPayload: [String: Any] = [
                    "type": "timeline_overlap",
                    "entries": [
                        [
                            "id": first.identifier,
                            "title": first.title,
                            "company": first.company,
                            "range": formattedRange(startRaw: first.startRaw, endRaw: first.endRaw)
                        ],
                        [
                            "id": second.identifier,
                            "title": second.title,
                            "company": second.company,
                            "range": formattedRange(startRaw: second.startRaw, endRaw: second.endRaw)
                        ]
                    ],
                    "message": "Employment entries for \(first.title) @ \(first.company) and \(second.title) @ \(second.company) overlap. Confirm whether the roles were concurrent or adjust the timeline.",
                    "suggested_fix": "Verify start/end months and ensure at most one role per interval unless positions were concurrent."
                ]
                conflicts.append(JSON(entryPayload))
            }
        }

        return conflicts
    }

    private func parsePartialDate(from value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        if let date = isoFormatter.date(from: value) {
            return date
        }

        if value.count == 7, value.contains("-") {
            let components = value.split(separator: "-")
            if components.count == 2,
               let year = Int(components[0]),
               let month = Int(components[1]) {
                var dateComponents = DateComponents()
                dateComponents.year = year
                dateComponents.month = month
                dateComponents.day = 1
                return Calendar.current.date(from: dateComponents)
            }
        }

        if value.count == 4, let year = Int(value) {
            var dateComponents = DateComponents()
            dateComponents.year = year
            dateComponents.month = 1
            dateComponents.day = 1
            return Calendar.current.date(from: dateComponents)
        }

        return nil
    }

    private func formattedRange(startRaw: String, endRaw: String?) -> String {
        let startDisplay = startRaw.isEmpty ? "?" : startRaw
        let endDisplay = endRaw?.isEmpty == false ? endRaw! : "Present"
        return "\(startDisplay) – \(endDisplay)"
    }
}
