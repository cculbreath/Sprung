//
//  InterviewDataStore.swift
//  Sprung
//
//  Lightweight persistence for onboarding interview tool outputs.
//
import Foundation
import SwiftyJSON
actor InterviewDataStore {
    private let baseURL: URL
    init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            Logger.error("Failed to locate application support directory for onboarding data")
            // Fallback to temporary directory
            baseURL = FileManager.default.temporaryDirectory.appendingPathComponent("Sprung/Onboarding/Data", isDirectory: true)
            return
        }
        let directory = appSupport.appendingPathComponent("Sprung/Onboarding/Data", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            Logger.debug("Failed to create onboarding data directory: \(error)")
        }
        baseURL = directory
    }
    func persist(dataType: String, payload: JSON) throws -> String {
        let identifier = UUID().uuidString
        let filename = "\(dataType)_\(identifier).json"
        let url = baseURL.appendingPathComponent(filename)
        guard let data = try? payload.rawData(options: [.prettyPrinted]) else {
            throw NSError(domain: "InterviewDataStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to encode payload for \(dataType)."
            ])
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw NSError(domain: "InterviewDataStore", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to persist data: \(error.localizedDescription)"
            ])
        }
        return identifier
    }
    func list(dataType: String) -> [JSON] {
        let prefix = "\(dataType)_"
        guard let files = try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.lastPathComponent.hasPrefix(prefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard
                    let data = try? Data(contentsOf: url),
                    let jsonObject = try? JSON(data: data)
                else {
                    return nil
                }
                return jsonObject
            }
    }
    func reset() async {
        guard let files = try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return
        }
        for url in files {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                Logger.debug("Failed to remove data file at \(url): \(error)")
            }
        }
    }
}
