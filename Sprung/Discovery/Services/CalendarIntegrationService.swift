//
//  CalendarIntegrationService.swift
//  Sprung
//
//  Service for integrating with macOS Calendar via EventKit.
//  Creates calendar events for networking events and interviews.
//

import Foundation
import EventKit

/// Service for calendar integration using EventKit
@Observable
@MainActor
final class CalendarIntegrationService {

    // MARK: - State

    private let eventStore = EKEventStore()

    private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    private(set) var isAuthorized: Bool = false
    private(set) var availableCalendars: [EKCalendar] = []
    private(set) var selectedCalendarIdentifier: String?

    // MARK: - Initialization

    init() {
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Update authorization status
    func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = authorizationStatus == .fullAccess

        if isAuthorized {
            loadCalendars()
        }
    }

    // MARK: - Calendar Management

    /// Load available calendars
    private func loadCalendars() {
        availableCalendars = eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title < $1.title }
    }

    /// Get the selected calendar or default
    var targetCalendar: EKCalendar? {
        if let identifier = selectedCalendarIdentifier,
           let calendar = availableCalendars.first(where: { $0.calendarIdentifier == identifier }) {
            return calendar
        }
        return eventStore.defaultCalendarForNewEvents
    }

    // MARK: - Event Creation

    /// Create a calendar event for a networking event
    func createCalendarEvent(for networkingEvent: NetworkingEventOpportunity) async throws -> String {
        guard isAuthorized else {
            throw CalendarError.notAuthorized
        }

        guard let calendar = targetCalendar else {
            throw CalendarError.noCalendarAvailable
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = networkingEvent.name
        event.startDate = networkingEvent.date
        event.notes = buildEventNotes(for: networkingEvent)

        // Set end time (default 2 hours if not specified)
        if let endTimeStr = networkingEvent.endTime,
           let endDate = parseTime(endTimeStr, relativeTo: networkingEvent.date) {
            event.endDate = endDate
        } else {
            event.endDate = networkingEvent.date.addingTimeInterval(2 * 3600)
        }

        // Set location
        if networkingEvent.isVirtual {
            event.location = networkingEvent.virtualLink ?? "Virtual Event"
            if let link = networkingEvent.virtualLink {
                event.url = URL(string: link)
            }
        } else {
            event.location = networkingEvent.locationAddress ?? networkingEvent.location
        }

        // Add URL to notes or as structured location
        if let url = URL(string: networkingEvent.url) {
            event.url = url
        }

        // Add reminder 1 hour before
        let alarm = EKAlarm(relativeOffset: -3600)
        event.addAlarm(alarm)

        // Save the event
        try eventStore.save(event, span: .thisEvent)

        Logger.info("📅 Created calendar event: \(event.title ?? "Untitled")", category: .ai)

        return event.eventIdentifier
    }

    // MARK: - Helpers

    private func buildEventNotes(for event: NetworkingEventOpportunity) -> String {
        var notes: [String] = []

        if let description = event.eventDescription {
            notes.append(description)
        }

        notes.append("")
        notes.append("Event Type: \(event.eventType.rawValue)")

        if let organizer = event.organizer {
            notes.append("Organizer: \(organizer)")
        }

        if let cost = event.cost {
            notes.append("Cost: \(cost)")
        }

        notes.append("")
        notes.append("Event URL: \(event.url)")

        if let goal = event.goal {
            notes.append("")
            notes.append("📎 Your Goal: \(goal)")
        }

        if let pitch = event.pitchScript, !pitch.isEmpty {
            notes.append("")
            notes.append("📝 Elevator Pitch:")
            notes.append(pitch)
        }

        return notes.joined(separator: "\n")
    }

    private func parseTime(_ timeString: String, relativeTo date: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        guard let time = formatter.date(from: timeString) else { return nil }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute

        return calendar.date(from: components)
    }
}

// MARK: - Errors

enum CalendarError: LocalizedError {
    case notAuthorized
    case noCalendarAvailable
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access not authorized. Please grant access in System Settings."
        case .noCalendarAvailable:
            return "No writable calendar available."
        case .saveFailed(let error):
            return "Failed to save calendar event: \(error.localizedDescription)"
        }
    }
}
