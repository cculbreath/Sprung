//
//  GitEvidenceCollector.swift
//  Sprung
//
//  Deterministic git-history evidence gathering for GitAnalysisAgent.
//  Runs cheap git commands (no LLM) and renders the results as the
//  <git_evidence> block injected into the agent's initial context, so
//  proficiency claims are grounded in longitudinal evidence.
//
//  Shared by every GitAnalysisAgent construction site (GitIngestionKernel,
//  StandaloneKCExtractor).
//

import Foundation
import SwiftyJSON

enum GitEvidenceCollector {

    /// Upper bound on commits scanned by the full-history numstat pass.
    /// Keeps `git log --numstat` tractable on huge repositories; when the repo
    /// has more commits than this, longitudinal evidence covers only the most
    /// recent commits and a truncation notice is logged.
    private static let numstatCommitCap = 5_000

    // MARK: - Gathering

    /// Gathers raw git data for a repository: contributors, file types, recent
    /// commit subjects, branches, repo stats, per-directory churn/tenure, and
    /// monthly commit activity.
    static func gather(repoPath: String) async throws -> JSON {
        var data = JSON()

        // Get contributors
        let contributors = try await runGitCommand(["shortlog", "-sne", "HEAD"], in: repoPath)
        data["contributors"] = parseContributors(contributors)

        // Get file types breakdown
        let files = try await runGitCommand(["ls-files"], in: repoPath)
        data["fileTypes"] = parseFileTypes(files)

        // Get recent commit subjects (last 200)
        let commits = try await runGitCommand([
            "log", "-200", "--format=%h|%an|%s"
        ], in: repoPath)
        data["recentCommits"] = parseCommits(commits)

        // Get branch info
        let branches = try await runGitCommand(["branch", "-a"], in: repoPath)
        data["branches"] = JSON(branches.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) })

        // Get repo stats
        let totalCommits = try await runGitCommand(["rev-list", "--count", "HEAD"], in: repoPath)
        data["totalCommits"].int = Int(totalCommits.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Get first and last commit dates
        let firstCommit = try await runGitCommand(["log", "--reverse", "--format=%ci", "-1"], in: repoPath)
        let lastCommit = try await runGitCommand(["log", "--format=%ci", "-1"], in: repoPath)
        data["firstCommit"].string = firstCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        data["lastCommit"].string = lastCommit.trimmingCharacters(in: .whitespacesAndNewlines)

        // Longitudinal evidence over the commit history: per-directory churn/tenure
        // and monthly commit activity, from a single numstat pass (capped so huge
        // repositories stay tractable).
        let totalCommitCount = data["totalCommits"].intValue
        if totalCommitCount > numstatCommitCap {
            Logger.info(
                "Git numstat evidence truncated to the most recent \(numstatCommitCap) of \(totalCommitCount) commits",
                category: .ai
            )
        }
        let numstat = try await runGitCommand([
            "log", "-n", "\(numstatCommitCap)", "--numstat", "--date=short", "--format=%H|%ad"
        ], in: repoPath)
        let history = parseNumstatHistory(numstat)
        data["directoryStats"] = history.directoryStats
        data["monthlyActivity"] = history.monthlyActivity

        return data
    }

    // MARK: - Rendering

    /// Renders gathered git data as readable evidence for the agent's initial context.
    /// High-signal aggregates come first so the trailing subject list absorbs truncation.
    static func render(_ data: JSON) -> String {
        let maxLength = 8_000
        var sections: [String] = []

        var overview = "### Overview\n"
        overview += "Total commits: \(data["totalCommits"].intValue)\n"
        overview += "First commit: \(data["firstCommit"].stringValue)\n"
        overview += "Last commit: \(data["lastCommit"].stringValue)"
        let contributors = data["contributors"].arrayValue.prefix(10).map {
            "\($0["name"].stringValue) (\($0["commits"].intValue) commits)"
        }
        if !contributors.isEmpty {
            overview += "\nContributors: " + contributors.joined(separator: ", ")
        }
        sections.append(overview)

        let fileTypes = data["fileTypes"].arrayValue.prefix(15).map {
            "\($0["extension"].stringValue) (\($0["count"].intValue))"
        }
        if !fileTypes.isEmpty {
            sections.append("### File Types\n" + fileTypes.joined(separator: ", "))
        }

        let dirStats = data["directoryStats"].arrayValue
        if !dirStats.isEmpty {
            // Label honestly when the numstat pass was capped — tenure/recency
            // below then reflect only the most recent commits.
            let coverage = data["totalCommits"].intValue > numstatCommitCap
                ? "most recent \(numstatCommitCap) commits"
                : "full history"
            var lines = [
                "### Activity by Top-Level Directory (\(coverage))",
                "directory | commits | +lines | -lines | first | last"
            ]
            for dir in dirStats.prefix(25) {
                lines.append(
                    "\(dir["directory"].stringValue) | \(dir["commits"].intValue) | "
                    + "\(dir["linesAdded"].intValue) | \(dir["linesDeleted"].intValue) | "
                    + "\(dir["firstCommit"].stringValue) | \(dir["lastCommit"].stringValue)"
                )
            }
            sections.append(lines.joined(separator: "\n"))
        }

        let monthly = data["monthlyActivity"].arrayValue
        if !monthly.isEmpty {
            let entries = monthly.map { "\($0["month"].stringValue): \($0["commits"].intValue)" }
            sections.append("### Commit Activity by Month\n" + entries.joined(separator: ", "))
        }

        let recentCommits = data["recentCommits"].arrayValue
        if !recentCommits.isEmpty {
            let lines = recentCommits.map { "- \($0["message"].stringValue)" }
            sections.append("### Recent Commit Subjects (newest first, up to 200)\n" + lines.joined(separator: "\n"))
        }

        var rendered = sections.joined(separator: "\n\n")
        if rendered.count > maxLength {
            rendered = String(rendered.prefix(maxLength)) + "\n[evidence truncated]"
        }
        return rendered
    }

    // MARK: - Parsing

    /// Parses `git log --numstat --date=short --format=%H|%ad` output into
    /// per-top-level-directory aggregates and monthly commit counts.
    private static func parseNumstatHistory(_ output: String) -> (directoryStats: JSON, monthlyActivity: JSON) {
        struct DirAggregate {
            var commits = 0
            var linesAdded = 0
            var linesDeleted = 0
            var firstCommitDate = ""
            var lastCommitDate = ""
        }

        var dirAggregates: [String: DirAggregate] = [:]
        var monthlyCounts: [String: Int] = [:]

        var currentDate = ""
        var currentCommitDirs: Set<String> = []

        func flushCommit(date: String) {
            for dir in currentCommitDirs {
                var agg = dirAggregates[dir] ?? DirAggregate()
                agg.commits += 1
                if agg.firstCommitDate.isEmpty || date < agg.firstCommitDate { agg.firstCommitDate = date }
                if agg.lastCommitDate.isEmpty || date > agg.lastCommitDate { agg.lastCommitDate = date }
                dirAggregates[dir] = agg
            }
            currentCommitDirs = []
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)

            // Commit header: "<40-hex-hash>|YYYY-MM-DD"
            if let pipeIndex = line.firstIndex(of: "|"),
               line.distance(from: line.startIndex, to: pipeIndex) == 40,
               line.prefix(40).allSatisfy({ $0.isHexDigit }) {
                flushCommit(date: currentDate)
                currentDate = String(line[line.index(after: pipeIndex)...])
                monthlyCounts[String(currentDate.prefix(7)), default: 0] += 1
                continue
            }

            // Numstat line: "<added>\t<deleted>\t<path>" ("-" for binary files)
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }

            let dir = topLevelDirectory(forNumstatPath: String(parts[2]))
            currentCommitDirs.insert(dir)

            var agg = dirAggregates[dir] ?? DirAggregate()
            agg.linesAdded += Int(parts[0]) ?? 0
            agg.linesDeleted += Int(parts[1]) ?? 0
            if agg.firstCommitDate.isEmpty || currentDate < agg.firstCommitDate { agg.firstCommitDate = currentDate }
            if agg.lastCommitDate.isEmpty || currentDate > agg.lastCommitDate { agg.lastCommitDate = currentDate }
            dirAggregates[dir] = agg
        }
        flushCommit(date: currentDate)

        let directoryStats = dirAggregates
            .sorted { $0.value.commits > $1.value.commits }
            .map { dir, agg -> [String: Any] in
                [
                    "directory": dir,
                    "commits": agg.commits,
                    "linesAdded": agg.linesAdded,
                    "linesDeleted": agg.linesDeleted,
                    "firstCommit": agg.firstCommitDate,
                    "lastCommit": agg.lastCommitDate
                ]
            }

        let monthlyActivity = monthlyCounts
            .sorted { $0.key < $1.key }
            .map { month, count -> [String: Any] in
                ["month": month, "commits": count]
            }

        return (JSON(directoryStats), JSON(monthlyActivity))
    }

    /// Extracts the top-level directory from a numstat path, normalizing rename syntax
    /// like "src/{old => new}/file.swift" and "old.txt => new.txt".
    private static func topLevelDirectory(forNumstatPath rawPath: String) -> String {
        var path = rawPath

        // Brace rename: "a/{b => c}/d" → "a/c/d"
        while let openBrace = path.range(of: "{"),
              let arrow = path.range(of: " => ", range: openBrace.upperBound..<path.endIndex),
              let closeBrace = path.range(of: "}", range: arrow.upperBound..<path.endIndex) {
            let newComponent = String(path[arrow.upperBound..<closeBrace.lowerBound])
            path.replaceSubrange(openBrace.lowerBound..<closeBrace.upperBound, with: newComponent)
        }

        // Whole-path rename: "old.txt => new.txt" → "new.txt"
        if let arrow = path.range(of: " => ") {
            path = String(path[arrow.upperBound...])
        }

        // Normalize any doubled slashes from empty rename components ("a/{ => b}/c")
        while path.contains("//") {
            path = path.replacingOccurrences(of: "//", with: "/")
        }

        guard let slashIndex = path.firstIndex(of: "/") else {
            return "(root)"
        }
        return String(path[..<slashIndex])
    }

    private static func parseContributors(_ output: String) -> JSON {
        var contributors: [[String: Any]] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "\t", maxSplits: 1)
            if parts.count == 2 {
                let commits = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
                let authorPart = String(parts[1])
                var name = authorPart
                var email = ""
                if let emailStart = authorPart.firstIndex(of: "<"),
                   let emailEnd = authorPart.firstIndex(of: ">") {
                    name = String(authorPart[..<emailStart]).trimmingCharacters(in: .whitespaces)
                    email = String(authorPart[authorPart.index(after: emailStart)..<emailEnd])
                }
                contributors.append([
                    "name": name,
                    "email": email,
                    "commits": commits
                ])
            }
        }
        return JSON(contributors)
    }

    private static func parseFileTypes(_ output: String) -> JSON {
        var extensionCounts: [String: Int] = [:]
        for line in output.split(separator: "\n") {
            let ext = (String(line) as NSString).pathExtension.lowercased()
            if !ext.isEmpty {
                extensionCounts[ext, default: 0] += 1
            }
        }
        let sorted = extensionCounts.sorted { $0.value > $1.value }.prefix(20)
        return JSON(sorted.map { ["extension": $0.key, "count": $0.value] })
    }

    private static func parseCommits(_ output: String) -> JSON {
        var commits: [[String: String]] = []
        for line in output.split(separator: "\n") {
            let parts = String(line).split(separator: "|", maxSplits: 2)
            if parts.count == 3 {
                commits.append([
                    "hash": String(parts[0]),
                    "author": String(parts[1]),
                    "message": String(parts[2])
                ])
            }
        }
        return JSON(commits)
    }

    // MARK: - Git Execution

    private static func runGitCommand(_ args: [String], in directory: String) async throws -> String {
        // Run process in detached task to avoid blocking the caller's actor
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git"] + args
            process.currentDirectoryURL = URL(fileURLWithPath: directory)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            // IMPORTANT: Read output BEFORE waitUntilExit to avoid deadlock
            // If we wait first, the pipe buffer can fill up and block the process
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}
