//
//  WebArchiveExtractor.swift
//  PhysCloudResume
//
//  Created by Claude on 7/12/25.
//

import Foundation

/// Utility to extract HTML content from Safari .webarchive files for testing LinkedIn extraction
class WebArchiveExtractor {
    
    /// Extract main HTML content from a .webarchive file
    static func extractHTML(from webArchivePath: String) -> String? {
        guard let data = NSData(contentsOfFile: webArchivePath) else {
            Logger.error("🚨 Could not read webarchive file: \(webArchivePath)")
            return nil
        }
        
        do {
            // Parse the webarchive plist
            guard let webArchive = try PropertyListSerialization.propertyList(
                from: data as Data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                Logger.error("🚨 Could not parse webarchive as plist")
                return nil
            }
            
            // Extract the main resource
            guard let mainResource = webArchive["WebMainResource"] as? [String: Any] else {
                Logger.error("🚨 Could not find WebMainResource in webarchive")
                return nil
            }
            
            // Get the HTML data
            guard let webResourceData = mainResource["WebResourceData"] as? Data else {
                Logger.error("🚨 Could not find WebResourceData in main resource")
                return nil
            }
            
            // Convert to string
            guard let htmlString = String(data: webResourceData, encoding: .utf8) else {
                Logger.error("🚨 Could not decode HTML data as UTF-8")
                return nil
            }
            
            Logger.info("✅ Successfully extracted HTML from webarchive (\(htmlString.count) characters)")
            return htmlString
            
        } catch {
            Logger.error("🚨 Error parsing webarchive: \(error)")
            return nil
        }
    }
    
    /// Test LinkedIn extraction using a webarchive file
    static func testLinkedInExtractionFromWebArchive(
        webArchivePath: String,
        jobAppStore: JobAppStore
    ) -> JobApp? {
        guard let html = extractHTML(from: webArchivePath) else {
            return nil
        }
        
        Logger.info("🧪 Testing LinkedIn extraction from webarchive: \(webArchivePath)")
        
        // Run debug analysis first
        JobApp.debugLinkedInPageStructure(html: html)
        
        // Test actual extraction
        if let jobApp = JobApp.parseLinkedInJobListing(html: html, url: "webarchive://\(webArchivePath)") {
            Logger.info("✅ Webarchive extraction successful: \(jobApp.jobPosition) at \(jobApp.companyName)")
            return jobApp
        } else {
            Logger.warning("⚠️ Webarchive extraction failed")
            return nil
        }
    }
}