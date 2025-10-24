//
//  DebugLog.swift
//  Sprung
//
//  Minimal debug logging helper for the onboarding feature.
//

import Foundation

@inline(__always) func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    print("🔎", message())
#endif
}

