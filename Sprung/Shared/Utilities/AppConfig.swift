//
//  AppConfig.swift
//  Sprung
//
//  Centralized non-secret configuration constants.
//

import Foundation

enum AppConfig {
    static let openRouterBaseURL = "https://openrouter.ai"
    static let openRouterAPIPath = "api"
    static let openRouterVersion = "v1"
    static let openRouterHeaders: [String: String] = [
        "HTTP-Referer": "https://github.com/cculbreath/Sprung",
        "X-Title": "Sprung",
    ]
}

