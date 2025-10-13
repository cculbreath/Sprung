//
//  DebugFileWriter.swift
//  Sprung
//
//  Lightweight helper for writing debug artifacts to disk.
//

import Foundation

enum DebugFileWriter {
    /// Writes the given string to a UTF‑8 file whose name begins with `prefix`
    /// (followed by a timestamp) and prints the resulting path.  Returns the
    /// file URL on success, or `nil` on failure.
    @discardableResult
    static func write(_ text: String, prefix: String, ext: String = "html") -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let ts = formatter.string(from: .init())
        let filename = "\(prefix)-\(ts).\(ext)"

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(filename)

        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            Logger.debug("🪵 Failed to write debug file \(filename): \(error.localizedDescription)")
            return nil
        }
    }
}
