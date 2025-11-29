import Foundation
import SwiftyJSON

/// Tool that analyzes a local git repository to extract skills and achievements.
/// Uses git attribution to filter contributions and dispatches analysis to identify
/// demonstrated competencies from the codebase.
struct ScanGitRepoTool: InterviewTool {
    private static let schema: JSONSchema = {
        let properties: [String: JSONSchema] = [
            "repo_path": JSONSchema(
                type: .string,
                description: "Absolute path to the local git repository to analyze."
            ),
            "author_filter": JSONSchema(
                type: .string,
                description: "Optional git author name or email to filter commits. If not provided, will analyze all commits and suggest filtering options."
            ),
            "timeline_entry_id": JSONSchema(
                type: .string,
                description: "Optional ID of the timeline entry this repo relates to. If provided, analysis will be scoped to that role."
            )
        ]
        return JSONSchema(
            type: .object,
            description: """
                Analyze a local git repository to extract demonstrated skills and achievements.

                WORKFLOW:
                1. Call without author_filter first to see contributor breakdown
                2. Call again with author_filter to analyze specific contributor's work
                3. Use results to generate knowledge cards

                RETURNS:
                - Without author_filter: List of contributors with commit counts
                - With author_filter: Analysis of languages, frameworks, patterns, and achievements
                """,
            properties: properties,
            required: ["repo_path"],
            additionalProperties: false
        )
    }()

    private unowned let coordinator: OnboardingInterviewCoordinator

    init(coordinator: OnboardingInterviewCoordinator) {
        self.coordinator = coordinator
    }

    var name: String { OnboardingToolName.scanGitRepo.rawValue }
    var description: String { "Analyze a git repository to extract coding skills and achievements. Supports author filtering for multi-contributor repos." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        let repoPath = params["repo_path"].stringValue
        let authorFilter = params["author_filter"].string
        let timelineEntryId = params["timeline_entry_id"].string

        // Validate repo path
        guard !repoPath.isEmpty else {
            return .error(.invalidParameters("repo_path is required"))
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: repoPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .error(.executionFailed("Path does not exist or is not a directory: \(repoPath)"))
        }

        // Check if it's a git repo
        let gitDir = (repoPath as NSString).appendingPathComponent(".git")
        guard fileManager.fileExists(atPath: gitDir) else {
            return .error(.executionFailed("Not a git repository: \(repoPath)"))
        }

        if let authorFilter = authorFilter {
            // Perform full analysis filtered by author
            return await analyzeRepoForAuthor(repoPath: repoPath, author: authorFilter, timelineEntryId: timelineEntryId)
        } else {
            // Return contributor breakdown
            return await getContributorBreakdown(repoPath: repoPath)
        }
    }

    /// Get a breakdown of contributors in the repo
    private func getContributorBreakdown(repoPath: String) async -> ToolResult {
        do {
            // Get contributor stats using git shortlog
            let shortlogOutput = try runGitCommand(["shortlog", "-sne", "HEAD"], in: repoPath)

            var contributors: [[String: Any]] = []
            for line in shortlogOutput.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Format: "   123\tName <email>"
                let parts = trimmed.split(separator: "\t", maxSplits: 1)
                if parts.count == 2 {
                    let commits = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
                    let authorPart = String(parts[1])

                    // Parse name and email
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

            // Get file type breakdown
            let fileTypes = try getFileTypeBreakdown(repoPath: repoPath)

            var response = JSON()
            response["status"].string = "completed"
            response["repo_path"].string = repoPath
            response["contributors"] = JSON(contributors)
            response["file_types"] = JSON(fileTypes)
            response["message"].string = """
                Found \(contributors.count) contributor(s). To analyze a specific contributor's work, \
                call scan_git_repo again with author_filter set to their name or email.
                """
            response["next_action"].string = "Call scan_git_repo with author_filter to analyze specific contributor"

            return .immediate(response)
        } catch {
            return .error(.executionFailed("Failed to analyze repository: \(error.localizedDescription)"))
        }
    }

    /// Analyze the repo for a specific author
    private func analyzeRepoForAuthor(repoPath: String, author: String, timelineEntryId: String?) async -> ToolResult {
        do {
            // Get commits by this author
            let logOutput = try runGitCommand(
                ["log", "--author=\(author)", "--pretty=format:%H|%s|%ad", "--date=short", "--no-merges"],
                in: repoPath
            )

            let commits = logOutput.split(separator: "\n").map { line -> [String: String] in
                let parts = line.split(separator: "|", maxSplits: 2)
                return [
                    "hash": !parts.isEmpty ? String(parts[0]) : "",
                    "message": parts.count > 1 ? String(parts[1]) : "",
                    "date": parts.count > 2 ? String(parts[2]) : ""
                ]
            }

            // Get files changed by this author
            let filesOutput = try runGitCommand(
                ["log", "--author=\(author)", "--pretty=format:", "--name-only", "--no-merges"],
                in: repoPath
            )

            var fileCounts: [String: Int] = [:]
            var extensionCounts: [String: Int] = [:]

            for line in filesOutput.split(separator: "\n") where !line.isEmpty {
                let file = String(line)
                fileCounts[file, default: 0] += 1

                let ext = (file as NSString).pathExtension.lowercased()
                if !ext.isEmpty {
                    extensionCounts[ext, default: 0] += 1
                }
            }

            // Analyze commit messages for patterns
            let commitMessages = commits.compactMap { $0["message"] }
            let patterns = analyzeCommitPatterns(commitMessages)

            // Build analysis summary
            let topFiles = fileCounts.sorted { $0.value > $1.value }.prefix(20)
            let languageBreakdown = extensionCounts.sorted { $0.value > $1.value }

            var response = JSON()
            response["status"].string = "completed"
            response["repo_path"].string = repoPath
            response["author"].string = author
            response["commit_count"].int = commits.count
            response["date_range"] = JSON([
                "earliest": commits.last?["date"] ?? "",
                "latest": commits.first?["date"] ?? ""
            ])
            response["languages"] = JSON(languageBreakdown.map { ["extension": $0.key, "file_changes": $0.value] })
            response["top_files"] = JSON(topFiles.map { ["file": $0.key, "changes": $0.value] })
            response["commit_patterns"] = JSON(patterns)

            if let timelineEntryId = timelineEntryId {
                response["timeline_entry_id"].string = timelineEntryId
            }

            response["suggested_skills"] = JSON(inferSkillsFromAnalysis(
                languages: languageBreakdown.map { $0.key },
                patterns: patterns,
                topFiles: topFiles.map { $0.key }
            ))

            response["next_action"].string = """
                Use this analysis to call generate_knowledge_card. Pass this data as evidence \
                for the relevant timeline entry.
                """

            return .immediate(response)
        } catch {
            return .error(.executionFailed("Failed to analyze author contributions: \(error.localizedDescription)"))
        }
    }

    /// Run a git command and return output
    private func runGitCommand(_ args: [String], in directory: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Get file type breakdown for the repo
    private func getFileTypeBreakdown(repoPath: String) throws -> [[String: Any]] {
        let output = try runGitCommand(["ls-files"], in: repoPath)
        var extensionCounts: [String: Int] = [:]

        for line in output.split(separator: "\n") {
            let ext = (String(line) as NSString).pathExtension.lowercased()
            if !ext.isEmpty {
                extensionCounts[ext, default: 0] += 1
            }
        }

        return extensionCounts
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map { ["extension": $0.key, "count": $0.value] }
    }

    /// Analyze commit messages for patterns
    private func analyzeCommitPatterns(_ messages: [String]) -> [String: Int] {
        var patterns: [String: Int] = [:]

        let patternKeywords: [String: [String]] = [
            "feature_development": ["add", "implement", "create", "new", "feature"],
            "bug_fixes": ["fix", "bug", "issue", "resolve", "patch"],
            "refactoring": ["refactor", "clean", "improve", "optimize", "restructure"],
            "testing": ["test", "spec", "coverage", "mock"],
            "documentation": ["doc", "readme", "comment", "explain"],
            "infrastructure": ["ci", "build", "deploy", "config", "setup"],
            "security": ["security", "auth", "permission", "encrypt", "vulnerability"]
        ]

        for message in messages {
            let lower = message.lowercased()
            for (pattern, keywords) in patternKeywords {
                if keywords.contains(where: { lower.contains($0) }) {
                    patterns[pattern, default: 0] += 1
                }
            }
        }

        return patterns
    }

    /// Infer skills from the analysis
    private func inferSkillsFromAnalysis(languages: [String], patterns: [String: Int], topFiles: [String]) -> [String] {
        var skills: [String] = []

        // Language-based skills
        let languageSkills: [String: String] = [
            "swift": "Swift/iOS/macOS Development",
            "py": "Python",
            "js": "JavaScript",
            "ts": "TypeScript",
            "tsx": "React/TypeScript",
            "jsx": "React",
            "go": "Go",
            "rs": "Rust",
            "java": "Java",
            "kt": "Kotlin",
            "rb": "Ruby",
            "php": "PHP",
            "cs": "C#/.NET",
            "cpp": "C++",
            "c": "C",
            "sql": "SQL/Database",
            "sh": "Shell Scripting",
            "yaml": "DevOps/Configuration",
            "yml": "DevOps/Configuration",
            "dockerfile": "Docker/Containerization"
        ]

        for lang in languages {
            if let skill = languageSkills[lang] {
                skills.append(skill)
            }
        }

        // Pattern-based skills
        if (patterns["testing"] ?? 0) > 5 {
            skills.append("Test-Driven Development")
        }
        if (patterns["infrastructure"] ?? 0) > 3 {
            skills.append("CI/CD Pipeline Development")
        }
        if (patterns["refactoring"] ?? 0) > 5 {
            skills.append("Code Quality & Refactoring")
        }
        if (patterns["security"] ?? 0) > 2 {
            skills.append("Security-Conscious Development")
        }

        // File-based skills
        let filePatterns: [String: String] = [
            "api": "API Development",
            "graphql": "GraphQL",
            "rest": "REST API Design",
            "websocket": "Real-time Communication",
            "auth": "Authentication/Authorization",
            "cache": "Caching Strategies",
            "queue": "Message Queues",
            "migration": "Database Migrations"
        ]

        for file in topFiles {
            let lower = file.lowercased()
            for (pattern, skill) in filePatterns {
                if lower.contains(pattern) && !skills.contains(skill) {
                    skills.append(skill)
                }
            }
        }

        return Array(Set(skills)).sorted()
    }
}
