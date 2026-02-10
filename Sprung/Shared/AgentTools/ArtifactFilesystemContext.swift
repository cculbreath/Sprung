//
//  ArtifactFilesystemContext.swift
//  Sprung
//
//  Manages the exported artifact filesystem root for tool execution.
//

import Foundation

/// Manages the exported artifact filesystem root for tool execution.
/// Set by the coordinator when artifacts are exported.
actor ArtifactFilesystemContext {
    private var _rootURL: URL?

    var rootURL: URL? {
        _rootURL
    }

    func setRoot(_ url: URL?) {
        _rootURL = url
    }

    /// Initializer for dependency injection
    init(rootURL: URL? = nil) {
        self._rootURL = rootURL
    }
}
