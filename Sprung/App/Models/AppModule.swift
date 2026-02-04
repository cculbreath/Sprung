//
//  AppModule.swift
//  Sprung
//
//  Defines application modules accessible via the icon bar.
//

import SwiftUI

/// Application modules accessible via icon bar
enum AppModule: String, CaseIterable, Identifiable, Codable {
    case resumeEditor = "resumeEditor"
    case pipeline = "pipeline"
    case sources = "sources"
    case dailyTasks = "dailyTasks"
    case weeklyReview = "weeklyReview"
    case events = "events"
    case contacts = "contacts"
    case profile = "profile"
    case experience = "experience"
    case references = "references"

    var id: String { rawValue }

    /// SF Symbol name for the module
    var icon: String {
        switch self {
        case .pipeline: return "square.stack.3d.down.forward"
        case .resumeEditor: return "pencil.and.list.clipboard"
        case .dailyTasks: return "figure.mind.and.body"
        case .sources: return "signpost.right.and.left"
        case .events: return "person.line.dotted.person.fill"
        case .contacts: return "teletype.answer"
        case .weeklyReview: return "calendar.day.timeline.left"
        case .references: return "brain.head.profile"
        case .experience: return "building.columns"
        case .profile: return "person.text.rectangle"
        }
    }

    /// Display label for the module
    var label: String {
        switch self {
        case .pipeline: return "Pipeline"
        case .resumeEditor: return "Resume Editor"
        case .dailyTasks: return "Daily Tasks"
        case .sources: return "Job Sources"
        case .events: return "Events"
        case .contacts: return "Contacts"
        case .weeklyReview: return "Weekly Review"
        case .references: return "References"
        case .experience: return "Experience"
        case .profile: return "Profile"
        }
    }

    /// Short description for tooltips
    var description: String {
        switch self {
        case .pipeline: return "Kanban board for job applications"
        case .resumeEditor: return "Create and customize resumes"
        case .dailyTasks: return "Today's tasks and time tracking"
        case .sources: return "Job boards and career sites"
        case .events: return "Networking events pipeline"
        case .contacts: return "Professional contacts CRM"
        case .weeklyReview: return "Goals progress and reflection"
        case .references: return "Knowledge, writing, skills, titles, dossier"
        case .experience: return "Experience defaults editor"
        case .profile: return "Applicant profile settings"
        }
    }

    /// Keyboard shortcut number (1-9, 0)
    var shortcutNumber: String {
        switch self {
        case .resumeEditor: return "1"
        case .pipeline: return "2"
        case .sources: return "3"
        case .dailyTasks: return "4"
        case .weeklyReview: return "5"
        case .events: return "6"
        case .contacts: return "7"
        case .profile: return "8"
        case .experience: return "9"
        case .references: return "0"
        }
    }

    /// Icon bar sections separated by dividers
    static var iconBarSections: [[AppModule]] {
        [
            [.dailyTasks, .weeklyReview],
            [.resumeEditor, .pipeline, .sources],
            [.events, .contacts],
            [.profile, .experience, .references],
        ]
    }

    /// Whether this module requires a focused job to function
    var requiresJobContext: Bool {
        switch self {
        case .resumeEditor: return true
        default: return false
        }
    }

    /// Whether to show the job picker in the toolbar
    var showsJobPicker: Bool {
        switch self {
        case .resumeEditor: return true
        default: return false
        }
    }

    /// Whether this module provides its own toolbar items
    var hasCustomToolbar: Bool {
        switch self {
        case .resumeEditor: return true
        default: return false
        }
    }

    /// Whether this module has its own footer bar
    var hasCustomFooter: Bool {
        switch self {
        case .resumeEditor: return true
        default: return false
        }
    }
}
