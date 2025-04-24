//
//  FileHandler.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/5/24.
//

import Foundation

class FileHandler {
    // Static file manager and application support directory
    static let fileManager = FileManager.default

    static let appSupportDirectory: URL = {
        // Ensure the Application Support directory exists
        let appSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        do {
            try fileManager.createDirectory(
                at: appSupportDirectory, withIntermediateDirectories: true, attributes: nil
            )
        } catch {
        }
        return appSupportDirectory
    }()

    static func readJsonUrl(filename: String = "resume-data.json") -> URL? {
        let path = appSupportDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: path.path) {
            return path
        } else {
            return nil
        }
    }

    static func jsonUrl(filename: String = "resume-data.json") -> URL {
        return appSupportDirectory.appendingPathComponent(filename)
    }

    static func readPdfUrl(filename: String = "rendered-resume.pdf") -> URL? {
        let path = appSupportDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: path.path) {
            return path
        } else {
            return nil
        }
    }

    static func pdfUrl(filename: String = "rendered-resume.pdf") -> URL {
        return appSupportDirectory.appendingPathComponent(filename)
    }

    // Function to save JSON to Application Support
    static func saveJSONToFile(jsonString: String) -> URL? {
        let fileURL = FileHandler.jsonUrl()
        do {
            if let jsonData = jsonString.data(using: .utf8) {
                try jsonData.write(to: fileURL)
                return fileURL
            }
        } catch {
        }
        return nil
    }
}
