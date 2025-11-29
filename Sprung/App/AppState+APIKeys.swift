//
//  AppState+APIKeys.swift
//  Sprung
//
//  Created by Christopher Culbreath on 5/20/25.
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
