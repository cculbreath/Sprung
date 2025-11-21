//
//  TemplateEditorModels.swift
//  Sprung
//
import Foundation
enum TemplateEditorTab: String, CaseIterable, Identifiable {
    case pdfTemplate = "PDF Template"
    case manifest = "Data Manifest"
    case txtTemplate = "Text Template"
    case seed = "Default Values"
    var id: String { rawValue }
}
struct TextFilterInfo: Identifiable {
    let id = UUID()
    let name: String
    let signature: String
    let description: String
    let snippet: String
}
