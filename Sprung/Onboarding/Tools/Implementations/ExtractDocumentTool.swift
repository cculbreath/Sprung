import Foundation
import SwiftyJSON
import SwiftOpenAI

struct ExtractDocumentTool: InterviewTool {
    private static let schema: JSONSchema = {
        JSONSchema(
            type: .object,
            description: "Extract semantically enriched text content from a PDF or DOCX file.",
            properties: [
                "file_url": JSONSchema(
                    type: .string,
                    description: "App-local file URL obtained from get_user_upload."
                ),
                "purpose": JSONSchema(
                    type: .string,
                    description: "Intended downstream use (e.g., resume_timeline, generic).",
                    enum: ["resume_timeline", "generic"]
                ),
                "return_types": JSONSchema(
                    type: .array,
                    description: "List of payloads to include in the response.",
                    items: JSONSchema(
                        type: .string,
                        enum: ["artifact_record", "applicant_profile", "skeleton_timeline"]
                    )
                ),
                "auto_persist": JSONSchema(
                    type: .boolean,
                    description: "Whether the artifact should be persisted immediately."
                ),
                "timeout_seconds": JSONSchema(
                    type: .integer,
                    description: "Optional timeout in seconds for the extraction pipeline."
                )
            ],
            required: ["file_url"],
            additionalProperties: false
        )
    }()

    private let extractionService: DocumentExtractionService

    init(extractionService: DocumentExtractionService) {
        self.extractionService = extractionService
    }

    var name: String { "extract_document" }
    var description: String { "Vendor-agnostic document extraction that returns enriched Markdown text." }
    var parameters: JSONSchema { Self.schema }

    func execute(_ params: JSON) async throws -> ToolResult {
        guard let fileURLString = params["file_url"].string,
              let fileURL = URL(string: fileURLString) else {
            throw ToolError.invalidParameters("file_url must be a valid URL string")
        }

        let purpose = params["purpose"].string ?? "generic"
        let returnTypes = params["return_types"].arrayValue.compactMap { $0.string }
        let autoPersist = params["auto_persist"].boolValue
        let timeout = params["timeout_seconds"].double

        let request = DocumentExtractionService.ExtractionRequest(
            fileURL: fileURL,
            purpose: purpose,
            returnTypes: returnTypes,
            autoPersist: autoPersist,
            timeout: timeout
        )

        do {
            let result = try await extractionService.extract(using: request)
            return .immediate(buildResponse(from: result, returnTypes: returnTypes))
        } catch let error as DocumentExtractionService.ExtractionError {
            return .error(.executionFailed(error.userFacingMessage))
        } catch {
            return .error(.executionFailed("Document extraction failed: \(error.localizedDescription)"))
        }
    }

    // MARK: - Helpers

    private func buildResponse(
        from result: DocumentExtractionService.ExtractionResult,
        returnTypes: [String]
    ) -> JSON {
        let normalizedReturnTypes = returnTypes.map { $0.lowercased() }
        let allowAll = normalizedReturnTypes.isEmpty
        let requested = Set(normalizedReturnTypes)

        var response = JSON()
        response["status"].string = result.status.rawValue

        if (allowAll || requested.contains("artifact_record")),
           let artifact = result.artifact {
            response["artifact_record"] = makeArtifactJSON(from: artifact)
        }

        if let profile = result.derivedApplicantProfile,
           (allowAll || requested.contains("applicant_profile")) {
            response["derived"]["applicant_profile"] = profile
        }

        if let timeline = result.derivedSkeletonTimeline,
           (allowAll || requested.contains("skeleton_timeline")) {
            response["derived"]["skeleton_timeline"] = timeline
        }

        response["quality"]["extraction_confidence"].double = result.quality.confidence
        response["quality"]["issues"] = JSON(result.quality.issues)
        response["persisted"].bool = result.persisted

        return response
    }

    private func makeArtifactJSON(from artifact: DocumentExtractionService.ArtifactRecord) -> JSON {
        var json = JSON()
        json["filename"].string = artifact.filename
        json["content_type"].string = artifact.contentType
        json["size_bytes"].int = artifact.sizeInBytes
        json["sha256"].string = artifact.sha256
        json["extracted_content"].string = artifact.extractedContent
        json["metadata"] = makeMetadataJSON(artifact.metadata)
        return json
    }

    private func makeMetadataJSON(_ metadata: [String: Any]) -> JSON {
        var json = JSON()
        for (key, value) in metadata {
            switch value {
            case let string as String:
                json[key].string = string
            case let bool as Bool:
                json[key].bool = bool
            case let int as Int:
                json[key].int = int
            case let double as Double:
                json[key].double = double
            case let number as NSNumber:
                json[key].double = number.doubleValue
            default:
                json[key].string = "\(value)"
            }
        }
        return json
    }
}
