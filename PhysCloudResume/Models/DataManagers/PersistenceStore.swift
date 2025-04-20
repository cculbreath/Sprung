//
//  PersistenceStore.swift
//  PhysCloudResume
//
//  A tiny abstraction that encapsulates the repetitive boiler‑plate that
//  previously lived in every *Store.swift file (manual JSON encoding/decoding,
//  file‑URL resolution, atomic writes, and error‑handling).
//
//  There are two pieces:
//  1. `PersistenceStore` – a protocol that any concrete store can adopt.  It
//     purposefully stays very small: load + save.  Domain stores remain free
//     to expose higher‑level helpers (e.g. `addJobApp(_:)`), but the actual
//     persistence mechanics are delegated.
//  2. `JSONFileStore` – a generic implementation that stores an *array* of
//     `Codable` entities in a single JSON file located under
//     Application Support.  It centralises all of the JSON coding and
//     file‑I/O that used to be duplicated across the codebase.
//
//  NOTE:  The existing domain stores (JobAppStore, ResStore, …) rely on
//  SwiftData for live‑object management.  They now *also* conform to
//  `PersistenceStore` by delegating their serialisation work to an internal
//  `JSONFileStore` instance.  This gives us automatic point‑in‑time backups
//  (via the JSON file) while removing ~100 lines of duplicated code.

import Foundation

// MARK: - Protocol

/// A minimal interface for persisting a homogeneous collection of models.
///
/// Concrete implementations decide *how* and *where* the data is stored
/// (JSON on disk, CloudKit, UserDefaults, etc.).  The only guarantee is that
/// the operations are synchronous and throw on failure, so callers can choose
/// their own error‑handling policy.
protocol PersistenceStore {
    associatedtype Entity: Codable & Identifiable

    /// Returns the current contents of the backing store, or an empty array if
    /// nothing has been saved yet.
    func load() throws -> [Entity]

    /// Persists the supplied collection, *overwriting* any previous data for
    /// the same `Entity` type.
    func save(_ entities: [Entity]) throws
}

// MARK: - JSON‑file implementation

/// A concrete `PersistenceStore` that serialises an array of `Codable` models
/// to a single JSON file under the application's *Application Support*
/// directory.  Writes are performed atomically to avoid corrupting partially
/// written files.
struct JSONFileStore<E: Codable & Identifiable>: PersistenceStore {
    typealias Entity = E

    // MARK: Configuration

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - filename:  The filename **without** any directory component.
    ///   - directory: The base directory to write under (defaults to
    ///                `.applicationSupportDirectory` in the user domain).
    ///   - encoder:   Optional custom encoder (e.g. to tweak date strategy).
    ///   - decoder:   Optional custom decoder (kept symmetrical to `encoder`).
    init(
        filename: String,
        directory: FileManager.SearchPathDirectory = .applicationSupportDirectory,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        // Build the on‑disk location.
        let url = FileManager.default.urls(
            for: directory, in: .userDomainMask
        ).first!

        fileURL = url.appendingPathComponent(filename)
        self.encoder = encoder
        self.decoder = decoder

        // Guarantee the parent directory exists.
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true, attributes: nil
        )
    }

    // MARK: PersistenceStore

    func load() throws -> [Entity] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([Entity].self, from: data)
    }

    func save(_ entities: [Entity]) throws {
        let data = try encoder.encode(entities)
        // `.atomic` avoids corruption on e.g. app crashes / power loss.
        try data.write(to: fileURL, options: .atomic)
    }
}
