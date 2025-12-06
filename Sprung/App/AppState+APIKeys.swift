//
//  AppState+APIKeys.swift
//  Sprung
//
//
import Foundation
extension AppState {
    var hasValidOpenRouterKey: Bool {
        !openRouterApiKey.isEmpty
    }
    var hasValidOpenAiKey: Bool {
        !openAiApiKey.isEmpty
    }
}
