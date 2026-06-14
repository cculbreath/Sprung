//
//  JobAppStatusTests.swift
//  SprungTests
//
//  Pure-logic coverage for the Statuses enum (JobApp pipeline state machine):
//  next/canAdvance/isTerminal, display names, ordering arrays, and icon/color
//  uniqueness. Does NOT touch JobApp persistence (Phase 3 owns that).
//

import XCTest
import SwiftUI
@testable import Sprung

final class JobAppStatusTests: XCTestCase {

    // MARK: - next / canAdvance

    func testNextProgressionChain() {
        XCTAssertEqual(Statuses.new.next, .queued)
        XCTAssertEqual(Statuses.queued.next, .inProgress)
        XCTAssertEqual(Statuses.inProgress.next, .submitted)
        XCTAssertEqual(Statuses.submitted.next, .interview)
        XCTAssertEqual(Statuses.interview.next, .offer)
        XCTAssertEqual(Statuses.offer.next, .accepted)
    }

    func testTerminalStatusesHaveNoNext() {
        XCTAssertNil(Statuses.accepted.next)
        XCTAssertNil(Statuses.rejected.next)
        XCTAssertNil(Statuses.withdrawn.next)
    }

    func testCanAdvanceMatchesNextPresence() {
        for status in Statuses.allCases {
            XCTAssertEqual(status.canAdvance, status.next != nil,
                           "\(status) canAdvance must agree with next != nil")
        }
    }

    func testFollowingNextReachesAcceptedFromNew() {
        var current: Statuses? = .new
        var steps = 0
        while let s = current, s.canAdvance, steps < 100 {
            current = s.next
            steps += 1
        }
        XCTAssertEqual(current, .accepted, "advancing from .new should terminate at .accepted")
        XCTAssertEqual(steps, 6, "new -> queued -> inProgress -> submitted -> interview -> offer -> accepted = 6 steps")
    }

    // MARK: - isTerminal

    func testIsTerminalFlags() {
        let terminal: Set<Statuses> = [.accepted, .rejected, .withdrawn]
        for status in Statuses.allCases {
            XCTAssertEqual(status.isTerminal, terminal.contains(status),
                           "\(status) isTerminal mismatch")
        }
    }

    // MARK: - displayName

    func testDisplayNameForNewIsIdentified() {
        XCTAssertEqual(Statuses.new.displayName, "Identified")
    }

    func testDisplayNameDefaultsToRawValue() {
        XCTAssertEqual(Statuses.queued.displayName, Statuses.queued.rawValue)
        XCTAssertEqual(Statuses.offer.displayName, "Offer")
        XCTAssertEqual(Statuses.interview.displayName, "Interview Pending")
    }

    // MARK: - Ordering arrays

    func testPipelineStatusesContainsEveryCaseOnce() {
        XCTAssertEqual(Set(Statuses.pipelineStatuses), Set(Statuses.allCases))
        XCTAssertEqual(Statuses.pipelineStatuses.count, Statuses.allCases.count,
                       "pipelineStatuses must have no duplicates")
    }

    func testPipelineStatusesIsInProgressionOrder() {
        XCTAssertEqual(Statuses.pipelineStatuses,
                       [.new, .queued, .inProgress, .submitted, .interview, .offer, .accepted, .rejected, .withdrawn])
    }

    func testSidebarOrderContainsEveryCaseOnce() {
        XCTAssertEqual(Set(Statuses.sidebarOrder), Set(Statuses.allCases))
        XCTAssertEqual(Statuses.sidebarOrder.count, Statuses.allCases.count,
                       "sidebarOrder must have no duplicates")
    }

    // MARK: - icon / color uniqueness

    func testEveryStatusHasNonEmptyIcon() {
        for status in Statuses.allCases {
            XCTAssertFalse(status.icon.isEmpty, "\(status) must have an SF Symbol icon")
        }
    }

    func testIconsAreUnique() {
        let icons = Statuses.allCases.map(\.icon)
        XCTAssertEqual(Set(icons).count, icons.count, "each status should have a distinct icon")
    }

    func testColorsAreUnique() {
        // Color is Equatable/Hashable for the named system colors used here.
        let colors = Statuses.allCases.map(\.color)
        XCTAssertEqual(Set(colors).count, colors.count, "each status should have a distinct color")
    }

    // MARK: - Raw value round-trip (Codable backing)

    func testRawValueRoundTrip() {
        for status in Statuses.allCases {
            XCTAssertEqual(Statuses(rawValue: status.rawValue), status)
        }
    }
}
