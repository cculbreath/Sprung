//
//  HandlebarsContextAugmentor.swift
//  Sprung
//
//  Adds derived fields expected by common Handlebars-based JSON Resume themes.
//

import Foundation

enum HandlebarsContextAugmentor {
    static func augment(_ context: [String: Any]) -> [String: Any] {
        var augmented = context

        augmentBasics(in: &augmented)
        augmentTopLevelSectionFlags(in: &augmented)
        augmentWork(in: &augmented)
        augmentVolunteer(in: &augmented)
        augmentSkills(in: &augmented)
        augmentEducation(in: &augmented)
        augmentAwards(in: &augmented)
        augmentPublications(in: &augmented)
        augmentInterests(in: &augmented)
        augmentLanguages(in: &augmented)
        augmentReferences(in: &augmented)

        return augmented
    }

    // MARK: - Basics

    private static func augmentBasics(in context: inout [String: Any]) {
        guard var basics = context["basics"] as? [String: Any] else { return }

        if let image = stringValue(basics["image"]), !image.isEmpty,
           (stringValue(basics["picture"])?.isEmpty ?? true) {
            basics["picture"] = image
        }
        if let picture = stringValue(basics["picture"]), !picture.isEmpty,
           (stringValue(basics["image"])?.isEmpty ?? true) {
            basics["image"] = picture
        }

        if let name = stringValue(basics["name"]), !name.isEmpty {
            basics["capitalName"] = name.uppercased()
        }
        if let label = stringValue(basics["label"]), !label.isEmpty {
            basics["capitalLabel"] = label.uppercased()
        }

        context["basics"] = basics

        // Root-level toggles expected by common themes
        let basicsPicture = basics["picture"] ?? basics["image"]
        context["pictureBool"] = truthy(basicsPicture)
        context["emailBool"] = truthy(basics["email"])
        context["phoneBool"] = truthy(basics["phone"])
        context["websiteBool"] = truthy(basics["website"])
        context["profilesBool"] = truthy(basics["profiles"])
        context["aboutBool"] = truthy(basics["summary"])

        if let location = basics["location"] as? [String: Any] {
            context["locationBool"] = truthy(location)
        }
    }

    private static func augmentTopLevelSectionFlags(in context: inout [String: Any]) {
        let sections: [(flag: String, key: String)] = [
            ("workBool", "work"),
            ("volunteerBool", "volunteer"),
            ("skillsBool", "skills"),
            ("educationBool", "education"),
            ("awardsBool", "awards"),
            ("publicationsBool", "publications"),
            ("interestsBool", "interests"),
            ("languagesBool", "languages"),
            ("referencesBool", "references")
        ]

        for section in sections {
            context[section.flag] = truthy(context[section.key])
        }
    }

    // MARK: - Work

    private static func augmentWork(in context: inout [String: Any]) {
        guard var work = dictionaryArray(from: context["work"]) else { return }

        for index in work.indices {
            var item = work[index]
            applyMonthYearFields(to: &item, startKey: "startDate", endKey: "endDate")

            if let endDate = stringValue(item["endDate"]), endDate.isEmpty,
               truthy(item["current"] ?? item["isCurrent"]) {
                item["endDateYear"] = "Present"
            }

            item["workHighlights"] = truthy(item["highlights"])
            work[index] = item
        }

        context["work"] = work
    }

    private static func augmentVolunteer(in context: inout [String: Any]) {
        guard var volunteer = dictionaryArray(from: context["volunteer"]) else { return }

        for index in volunteer.indices {
            var item = volunteer[index]
            applyMonthYearFields(to: &item, startKey: "startDate", endKey: "endDate")
            item["volunterHighlights"] = truthy(item["highlights"])
            item["volunteerHighlights"] = truthy(item["highlights"])
            volunteer[index] = item
        }

        context["volunteer"] = volunteer
    }

    private static func augmentSkills(in context: inout [String: Any]) {
        guard var skills = dictionaryArray(from: context["skills"]) else { return }
        for index in skills.indices {
            var item = skills[index]
            item["keywordsBool"] = truthy(item["keywords"])
            skills[index] = item
        }
        context["skills"] = skills
    }

    private static func augmentEducation(in context: inout [String: Any]) {
        guard var education = dictionaryArray(from: context["education"]) else { return }

        for index in education.indices {
            var item = education[index]
            applyMonthYearFields(to: &item, startKey: "startDate", endKey: "endDate")
            item["gpaBool"] = truthy(item["gpa"])
            item["educationCourses"] = truthy(item["courses"])
            education[index] = item
        }

        context["education"] = education
    }

    private static func augmentAwards(in context: inout [String: Any]) {
        guard var awards = dictionaryArray(from: context["awards"]) else { return }

        for index in awards.indices {
            var item = awards[index]
            applyDayMonthYearFields(to: &item, dateKey: "date")
            awards[index] = item
        }

        context["awards"] = awards
    }

    private static func augmentPublications(in context: inout [String: Any]) {
        guard var publications = dictionaryArray(from: context["publications"]) else { return }

        for index in publications.indices {
            var item = publications[index]
            applyDayMonthYearFields(to: &item, dateKey: "releaseDate")
            publications[index] = item
        }

        context["publications"] = publications
    }

    private static func augmentInterests(in context: inout [String: Any]) {
        guard var interests = dictionaryArray(from: context["interests"]) else { return }
        for index in interests.indices {
            var item = interests[index]
            item["keywordsBool"] = truthy(item["keywords"])
            interests[index] = item
        }
        context["interests"] = interests
    }

    private static func augmentLanguages(in context: inout [String: Any]) {
        guard var languages = dictionaryArray(from: context["languages"]) else { return }
        for index in languages.indices {
            var item = languages[index]
            // Ensure expected keys exist
            if item["language"] == nil, let name = item["name"] {
                item["language"] = name
            }
            languages[index] = item
        }
        context["languages"] = languages
    }

    private static func augmentReferences(in context: inout [String: Any]) {
        guard var references = dictionaryArray(from: context["references"]) else { return }
        for index in references.indices {
            var item = references[index]
            if item["reference"] == nil, let text = item["text"] {
                item["reference"] = text
            }
            references[index] = item
        }
        context["references"] = references
    }

    // MARK: - Helpers

    private static func truthy(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        if let array = value as? [Any] {
            return array.isEmpty == false
        }
        if let dict = value as? [String: Any] {
            return dict.isEmpty == false
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return true
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func dictionaryArray(from value: Any?) -> [[String: Any]]? {
        if let array = value as? [[String: Any]] {
            return array
        }
        if let array = value as? [Any] {
            var result: [[String: Any]] = []
            for element in array {
                if let dict = element as? [String: Any] {
                    result.append(dict)
                }
            }
            return result
        }
        return nil
    }

    private static func applyMonthYearFields(
        to item: inout [String: Any],
        startKey: String,
        endKey: String
    ) {
        if stringValue(item["startDateMonth"]) == nil || stringValue(item["startDateYear"]) == nil,
           let startString = stringValue(item[startKey]),
           let parts = DatePartsParser.monthYear(from: startString) {
            if let month = parts.month {
                item["startDateMonth"] = month
            }
            if let year = parts.year {
                item["startDateYear"] = year
            }
        }

        if stringValue(item["endDateMonth"]) == nil || stringValue(item["endDateYear"]) == nil {
            if let endString = stringValue(item[endKey]),
               let parts = DatePartsParser.monthYear(from: endString) {
                if let month = parts.month {
                    item["endDateMonth"] = month
                }
                if let year = parts.year {
                    item["endDateYear"] = year
                }
            } else if truthy(item[endKey]) == false {
                item["endDateYear"] = "Present"
            }
        }
    }

    private static func applyDayMonthYearFields(
        to item: inout [String: Any],
        dateKey: String
    ) {
        guard let dateString = stringValue(item[dateKey]),
              let parts = DatePartsParser.dayMonthYear(from: dateString) else {
            return
        }
        if let day = parts.day {
            item["day"] = day
        }
        if let month = parts.month {
            item["month"] = month
        }
        if let year = parts.year {
            item["year"] = year
        }
    }

    // MARK: - Date Parsing

    private enum DatePartsParser {
        struct Components {
            let day: String?
            let month: String?
            let year: String?
        }

        static func monthYear(from string: String) -> Components? {
            guard let date = parseDate(from: string, formats: ["yyyy-MM-dd", "yyyy-MM", "yyyy"]) else {
                return nil
            }
            let month: String? = monthFormatter.string(from: date).trimmingCharacters(in: .whitespaces)
            let year = yearFormatter.string(from: date)
            let monthWithSpace = month.map { $0.isEmpty ? "" : "\($0) " }
            return Components(day: nil, month: monthWithSpace, year: year)
        }

        static func dayMonthYear(from string: String) -> Components? {
            guard let date = parseDate(
                from: string,
                formats: ["yyyy-MM-dd", "yyyy-MM", "yyyy"]
            ) else {
                return nil
            }
            let dayString: String?
            if string.count >= 10 {
                dayString = dayFormatter.string(from: date)
            } else {
                dayString = nil
            }
            let month = monthFormatter.string(from: date)
            let year = yearFormatter.string(from: date)
            return Components(day: dayString, month: month, year: year)
        }

        private static func parseDate(from string: String, formats: [String]) -> Date? {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            for format in formats {
                dateFormatter.dateFormat = format
                if let date = dateFormatter.date(from: trimmed) {
                    return date
                }
            }
            return nil
        }

        private static let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter
        }()

        private static let monthFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "MMM"
            return formatter
        }()

        private static let yearFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy"
            return formatter
        }()

        private static let dayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "d"
            return formatter
        }()
    }
}
