//
//  TabList.swift
//  Sprung
//
//
enum TabList: String, CaseIterable, Codable {
    case listing = "Listing"
    case resume = "Résumé"
    case coverLetter = "Cover Letter"
    case submitApp = "Export"
    case none = "None"

    static var visibleCases: [TabList] {
        [.listing, .resume, .coverLetter, .submitApp]
    }
}
