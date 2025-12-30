//
//  TokenBudgetPolicy.swift
//  Sprung
//
//  Token budget policy for monitoring and warning on token usage.
//  Part of Milestone 0: Telemetry + budgets
//

import Foundation

/// Token budget policy configuration and enforcement
struct TokenBudgetPolicy {
    // MARK: - Budget Thresholds

    /// Target for first assistant turn (spec: <3k input tokens)
    static let firstTurnBudget: Int = 3_000

    /// Target for typical turns (spec: <6k input tokens)
    static let typicalTurnBudget: Int = 6_000

    /// Default hard stop threshold - triggers PRI reset safety net
    static let defaultHardStopBudget: Int = 75_000

    /// UserDefaults key for configurable hard stop
    private static let hardStopBudgetKey = "tokenBudgetHardStop"

    /// Hard stop threshold - configurable via Settings > Debug
    static var hardStopBudget: Int {
        let stored = UserDefaults.standard.integer(forKey: hardStopBudgetKey)
        return stored > 0 ? stored : defaultHardStopBudget
    }

    /// Set hard stop budget (for Settings UI)
    static func setHardStopBudget(_ value: Int) {
        UserDefaults.standard.set(value, forKey: hardStopBudgetKey)
    }

    /// Warning threshold (80% of hard stop)
    static var warningThreshold: Int {
        Int(Double(hardStopBudget) * 0.8)
    }

    // MARK: - Budget Status

    enum BudgetStatus: Equatable {
        case withinBudget
        case aboveTypical(Int)   // tokens over typical budget
        case warning(Int)        // tokens approaching hard stop
        case exceededHardStop(Int) // tokens over hard stop
    }

    // MARK: - Budget Checking

    /// Check token usage against budget thresholds
    /// - Parameters:
    ///   - inputTokens: Number of input tokens for the request
    ///   - isFirstTurn: Whether this is the first turn of the conversation
    /// - Returns: Budget status indicating if thresholds are exceeded
    static func checkBudget(inputTokens: Int, isFirstTurn: Bool) -> BudgetStatus {
        let effectiveTypicalBudget = isFirstTurn ? firstTurnBudget : typicalTurnBudget

        if inputTokens > hardStopBudget {
            return .exceededHardStop(inputTokens - hardStopBudget)
        } else if inputTokens > warningThreshold {
            return .warning(inputTokens - warningThreshold)
        } else if inputTokens > effectiveTypicalBudget {
            return .aboveTypical(inputTokens - effectiveTypicalBudget)
        }
        return .withinBudget
    }

    /// Log a budget warning if needed
    /// - Parameters:
    ///   - inputTokens: Number of input tokens
    ///   - isFirstTurn: Whether this is the first turn
    ///   - phase: Current interview phase
    ///   - source: Source of the request (for logging context)
    static func logBudgetWarning(
        inputTokens: Int,
        isFirstTurn: Bool,
        phase: String,
        source: String
    ) {
        let status = checkBudget(inputTokens: inputTokens, isFirstTurn: isFirstTurn)

        switch status {
        case .withinBudget:
            break
        case .aboveTypical(let over):
            Logger.warning(
                "⚠️ Token budget: \(inputTokens) tokens exceeds typical budget by \(over) (phase: \(phase), source: \(source))",
                category: .ai
            )
        case .warning(let over):
            Logger.warning(
                "🚨 Token budget WARNING: \(inputTokens) tokens approaching hard stop, over warning by \(over) (phase: \(phase), source: \(source))",
                category: .ai
            )
        case .exceededHardStop(let over):
            Logger.error(
                "🛑 Token budget EXCEEDED: \(inputTokens) tokens exceeds hard stop by \(over) (phase: \(phase), source: \(source))",
                category: .ai
            )
        }
    }
}

// MARK: - Request Telemetry

/// Telemetry data for a single LLM request
struct RequestTelemetry {
    let phase: String
    let substate: String?
    let toolsSentCount: Int
    let instructionsChars: Int
    let bundledDevMsgsCount: Int
    let inputTokens: Int?
    let outputTokens: Int?
    let cachedTokens: Int?
    let isFirstTurn: Bool
    let requestType: RequestType

    enum RequestType: String {
        case userMessage = "user_message"
        case developerMessage = "developer_message"
        case toolResponse = "tool_response"
        case batchedToolResponse = "batched_tool_response"
    }

    /// Log telemetry data for this request
    func log() {
        var components: [String] = []
        components.append("phase=\(phase)")
        if let substate = substate {
            components.append("substate=\(substate)")
        }
        components.append("tools=\(toolsSentCount)")
        components.append("instructions_chars=\(instructionsChars)")
        components.append("bundled_dev_msgs=\(bundledDevMsgsCount)")
        components.append("type=\(requestType.rawValue)")
        components.append("first_turn=\(isFirstTurn)")

        if let input = inputTokens {
            components.append("in=\(input)")
        }
        if let output = outputTokens {
            components.append("out=\(output)")
        }
        if let cached = cachedTokens, cached > 0 {
            components.append("cached=\(cached)")
        }

        Logger.info("📊 Request telemetry: \(components.joined(separator: ", "))", category: .ai)

        // Log budget warning if we have input tokens
        if let input = inputTokens {
            TokenBudgetPolicy.logBudgetWarning(
                inputTokens: input,
                isFirstTurn: isFirstTurn,
                phase: phase,
                source: requestType.rawValue
            )
        }
    }
}
