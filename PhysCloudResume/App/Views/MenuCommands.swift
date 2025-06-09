//
//  MenuCommands.swift
//  PhysCloudResume
//
//  Menu command definitions and notifications for the application.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Menu Command Notifications
extension Notification.Name {
    // Job Application Commands
    static let newJobApp = Notification.Name("newJobApp")
    static let bestJob = Notification.Name("bestJob")
    static let showSources = Notification.Name("showSources")
    
    // Resume Commands
    static let customizeResume = Notification.Name("customizeResume")
    static let clarifyCustomize = Notification.Name("clarifyCustomize")
    static let optimizeResume = Notification.Name("optimizeResume")
    static let showResumeInspector = Notification.Name("showResumeInspector")
    
    // Cover Letter Commands
    static let generateCoverLetter = Notification.Name("generateCoverLetter")
    static let batchCoverLetter = Notification.Name("batchCoverLetter")
    static let bestCoverLetter = Notification.Name("bestCoverLetter")
    static let committee = Notification.Name("committee")
    static let showCoverLetterInspector = Notification.Name("showCoverLetterInspector")
    
    // Text-to-Speech Commands
    static let startSpeaking = Notification.Name("startSpeaking")
    static let stopSpeaking = Notification.Name("stopSpeaking")
    static let restartSpeaking = Notification.Name("restartSpeaking")
    
    // Analysis Commands
    static let analyzeApplication = Notification.Name("analyzeApplication")
    
    // Window Commands (for toolbar buttons)
    static let showSettings = Notification.Name("showSettings")
    static let showApplicantProfile = Notification.Name("showApplicantProfile")
    static let showTemplateEditor = Notification.Name("showTemplateEditor")
    
    // Export Commands
    static let exportResumePDF = Notification.Name("exportResumePDF")
    static let exportResumeText = Notification.Name("exportResumeText")
    static let exportResumeJSON = Notification.Name("exportResumeJSON")
    static let exportCoverLetterPDF = Notification.Name("exportCoverLetterPDF")
    static let exportCoverLetterText = Notification.Name("exportCoverLetterText")
    static let exportAllCoverLetters = Notification.Name("exportAllCoverLetters")
    static let exportApplicationPacket = Notification.Name("exportApplicationPacket")
}