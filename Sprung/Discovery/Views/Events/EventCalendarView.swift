//
//  EventCalendarView.swift
//  Sprung
//
//  Calendar month view for networking events.
//  Shows events on a visual calendar with navigation between months.
//

import SwiftUI

struct EventCalendarView: View {
    let coordinator: DiscoveryCoordinator

    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()

    private let calendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation header
            monthHeader

            Divider()

            // Days of week header
            daysOfWeekHeader

            // Calendar grid
            calendarGrid

            Divider()

            // Selected week events
            selectedWeekEvents
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthYearString)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button {
                withAnimation {
                    displayedMonth = Date()
                    selectedDate = Date()
                }
            } label: {
                Text("Today")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                withAnimation {
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                }
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    // MARK: - Days of Week Header

    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = generateDaysInMonth()
        let rows = days.chunked(into: 7)

        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { date in
                        CalendarDayCell(
                            date: date,
                            isCurrentMonth: isInCurrentMonth(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            events: eventsForDate(date)
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedDate = date
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Selected Week Events

    private var selectedWeekEvents: some View {
        let weekEvents = eventsForWeek(containing: selectedDate)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedWeekString)
                    .font(.headline)

                Spacer()

                if weekEvents.isEmpty {
                    Text("No events this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            if weekEvents.isEmpty {
                Spacer()
            } else {
                List {
                    ForEach(daysWithEvents(in: weekEvents), id: \.self) { day in
                        Section(header: Text(dayHeaderString(for: day))) {
                            ForEach(eventsForDate(day).sorted { $0.date < $1.date }) { event in
                                NavigationLink {
                                    if event.needsDebrief {
                                        DebriefView(event: event, coordinator: coordinator)
                                    } else {
                                        EventPrepView(event: event, coordinator: coordinator)
                                    }
                                } label: {
                                    EventRowView(event: event)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        coordinator.eventStore.delete(event)
                                    } label: {
                                        Label("Delete Event", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var selectedWeekString: String {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: selectedDate) else {
            return "This Week"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekInterval.start)
        let end = formatter.string(from: calendar.date(byAdding: .day, value: -1, to: weekInterval.end) ?? weekInterval.end)
        return "\(start) – \(end)"
    }

    private func dayHeaderString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func eventsForWeek(containing date: Date) -> [NetworkingEventOpportunity] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return []
        }
        return coordinator.eventStore.allEvents.filter { event in
            event.date >= weekInterval.start && event.date < weekInterval.end
        }.sorted { $0.date < $1.date }
    }

    private func daysWithEvents(in events: [NetworkingEventOpportunity]) -> [Date] {
        var days: [Date] = []
        for event in events {
            let startOfDay = calendar.startOfDay(for: event.date)
            if !days.contains(where: { calendar.isDate($0, inSameDayAs: startOfDay) }) {
                days.append(startOfDay)
            }
        }
        return days.sorted()
    }

    // MARK: - Helpers

    private func generateDaysInMonth() -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1)
        else {
            return []
        }

        var days: [Date] = []
        var currentDate = monthFirstWeek.start

        while currentDate < monthLastWeek.end {
            days.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }

        return days
    }

    private func isInCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
    }

    private func eventsForDate(_ date: Date) -> [NetworkingEventOpportunity] {
        coordinator.eventStore.allEvents.filter { event in
            calendar.isDate(event.date, inSameDayAs: date)
        }
    }
}

// MARK: - Calendar Day Cell

struct CalendarDayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let events: [NetworkingEventOpportunity]

    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 2) {
            // Day number
            Text("\(calendar.component(.day, from: date))")
                .font(.system(.body, design: .rounded))
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(dayTextColor)

            // Event indicators
            if !events.isEmpty {
                HStack(spacing: 2) {
                    ForEach(events.prefix(3)) { event in
                        Circle()
                            .fill(eventColor(for: event))
                            .frame(width: 6, height: 6)
                    }
                    if events.count > 3 {
                        Text("+\(events.count - 3)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // Placeholder for consistent height
                Color.clear.frame(height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isToday ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private var dayTextColor: Color {
        if !isCurrentMonth {
            return .secondary.opacity(0.4)
        }
        if isSelected {
            return .white
        }
        return .primary
    }

    private var backgroundColor: Color {
        if isSelected {
            return .accentColor
        }
        if isToday {
            return .accentColor.opacity(0.1)
        }
        return .clear
    }

    private func eventColor(for event: NetworkingEventOpportunity) -> Color {
        if let recommendation = event.llmRecommendation {
            switch recommendation {
            case .strongYes: return .green
            case .yes: return .teal
            case .maybe: return .yellow
            case .skip: return .gray
            }
        }

        switch event.status {
        case .planned: return .blue
        case .attended, .debriefed: return .green
        case .skipped: return .gray
        default: return .orange
        }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
