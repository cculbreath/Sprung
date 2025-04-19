//
//  IndexProvider.swift
//  PhysCloudResume
//
//  Created by OpenAI Codex on 2025‑04‑17.
//
//  Thread‑safe, re‑entrant incremental integer generator.
//  Unlike the previous `static` counters this helper is an ordinary class
//  instance.  Each caller can keep its own provider, so indices are local to
//  the operation (e.g. building a Resume tree) and tests can reset the state
//  reliably.

import Foundation

public final class IndexProvider {
    private var nextValue: Int
    private let lock = NSLock()

    public init(startAt: Int = 0) {
        nextValue = startAt
    }

    /// Returns the next sequential integer value in a thread‑safe manner.
    @discardableResult
    public func make() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let value = nextValue
        nextValue += 1
        return value
    }

    /// Resets the sequence back to zero (useful in unit tests).
    public func reset(to value: Int = 0) {
        lock.lock()
        nextValue = value
        lock.unlock()
    }
}
