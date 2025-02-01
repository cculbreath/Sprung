//
//  FileHandler.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/5/24.
//

import Foundation

class FileHandler {
    static var fontsDone: Bool = true
    init() {
        if !FileHandler.fontsDone {
//      FileHandler.copyFontsToAppSupport()
            FileHandler.fontsDone = true
        }
    }

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
            print("Error creating Application Support directory: \(error)")
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
                print("JSON file saved successfully at \(fileURL.path)")
                return fileURL
            }
        } catch {
            print("Error saving JSON file: \(error)")
        }
        return nil
    }

    //  static func copyFontsToAppSupport() {
//    let fileManager = FileManager.default
//
//    // Get the app support directory
//    if let appSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
//      let destinationURL = appSupportDirectory.appendingPathComponent("_fonts")
//
//      // Create the Application Support subdirectory if it doesn't exist
    ////      do {
    ////        try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true, attributes: nil)
    ////      } catch {
    ////        print("Failed to create directory in Application Support: \(error)")
    ////        return
    ////      }
//
//      // Get the folder URL from the bundle
//      if let bundleFolderURL = Bundle.main.url(forResource: "cooper", withExtension: "otf", subdirectory: "scripts") {
//        do {
//          // Copy all contents of the folder from the bundle to Application Support
//          let folderContents = try fileManager.contentsOfDirectory(at: bundleFolderURL, includingPropertiesForKeys: nil)
//          for file in folderContents {
//            let destinationFileURL = destinationURL.appendingPathComponent(file.lastPathComponent)
//
//            // Check if file already exists in
//              try fileManager.copyItem(at: bundleFolderURL, to: appSupportDirectory)
//              print("Copied \(file.lastPathComponent) to Application Support")
//
//          }
//        } catch {
//          print("Failed to copy folder contents: \(error)")
//        }
//      } else {
//        print("Could not locate folder in bundle: scripts/_fonts")
//      }
//    } else {
//      print("Could not locate Application Support directory")
//    }
    //  }
}
