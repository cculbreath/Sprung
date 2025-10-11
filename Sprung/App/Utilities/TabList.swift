//
//  TabList.swift
//  Sprung
//
//  Created by Christopher Culbreath on .
//

enum TabList: String, CaseIterable, Codable {
    case listing = "Listing"
    case resume = "Résumé"
    case coverLetter = "Cover Letter"
    case submitApp = "Export"
    case none = "None"
}
