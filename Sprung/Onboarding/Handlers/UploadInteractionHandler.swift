//
//  UploadInteractionHandler.swift
//  Sprung
//
//  Handles file upload requests, targeted uploads (e.g., basics.image), and remote downloads.
//  Produces JSON payloads for tool continuations.
//

import Foundation
import Observation
import SwiftyJSON

@MainActor
@Observable
final class UploadInteractionHandler {
    // MARK: - Observable State

    private(set) var pendingUploadRequests: [OnboardingUploadRequest] = []
    private(set) var uploadedItems: [OnboardingUploadedItem] = []

    // MARK: - Private State

    private var uploadContinuationIds: [UUID: UUID] = [:]

    // MARK: - Dependencies

    private let uploadFileService: UploadFileService
    private let uploadStorage: OnboardingUploadStorage
    private let applicantProfileStore: ApplicantProfileStore
    private let dataStore: InterviewDataStore
    private let eventBus: EventCoordinator
    private var extractionProgressHandler: ExtractionProgressHandler?

    // MARK: - Init

    init(
        uploadFileService: UploadFileService,
        uploadStorage: OnboardingUploadStorage,
        applicantProfileStore: ApplicantProfileStore,
        dataStore: InterviewDataStore,
        eventBus: EventCoordinator,
        extractionProgressHandler: ExtractionProgressHandler?
    ) {
        self.uploadFileService = uploadFileService
        self.uploadStorage = uploadStorage
        self.applicantProfileStore = applicantProfileStore
        self.dataStore = dataStore
        self.eventBus = eventBus
        self.extractionProgressHandler = extractionProgressHandler
    }

    func updateExtractionProgressHandler(_ handler: ExtractionProgressHandler?) {
        extractionProgressHandler = handler
    }

    // MARK: - Presentation

    /// Presents an upload request to the user.
    func presentUploadRequest(_ request: OnboardingUploadRequest, continuationId: UUID) {
        removeUploadRequest(id: request.id)
        pendingUploadRequests.append(request)
        uploadContinuationIds[request.id] = continuationId
        Logger.info("📤 Upload request presented: \(request.metadata.title)", category: .ai)
    }

    // MARK: - Resolution

    /// Completes an upload with local file URLs.
    func completeUpload(id: UUID, fileURLs: [URL]) async -> (continuationId: UUID, payload: JSON)? {
        await handleUploadCompletion(id: id, fileURLs: fileURLs, originalURL: nil, cancelReason: nil)
    }

    /// Completes an upload by downloading from a remote URL.
    func completeUpload(id: UUID, link: URL) async -> (continuationId: UUID, payload: JSON)? {
        do {
            let temporaryURL = try await uploadFileService.downloadRemoteFile(from: link)
            defer { uploadFileService.cleanupTemporaryFile(at: temporaryURL) }
            return await handleUploadCompletion(id: id, fileURLs: [temporaryURL], originalURL: link, cancelReason: nil)
        } catch {
            return await resumeUpload(id: id, withError: error.localizedDescription)
        }
    }

    /// Skips an upload request (user chose not to upload).
    func skipUpload(id: UUID) async -> (continuationId: UUID, payload: JSON)? {
        await handleUploadCompletion(id: id, fileURLs: [], originalURL: nil, cancelReason: nil)
    }

    /// Cancels an upload request (assistant dismissed the card).
    func cancelUpload(id: UUID, reason: String?) async -> (continuationId: UUID, payload: JSON)? {
        await handleUploadCompletion(id: id, fileURLs: [], originalURL: nil, cancelReason: reason)
    }

    func cancelPendingUpload(reason: String?) async -> (continuationId: UUID, payload: JSON)? {
        guard let request = pendingUploadRequests.first else { return nil }
        return await cancelUpload(id: request.id, reason: reason)
    }

    // MARK: - Private Helpers

    private func handleUploadCompletion(
        id: UUID,
        fileURLs: [URL],
        originalURL: URL?,
        cancelReason: String?
    ) async -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = uploadContinuationIds[id] else {
            Logger.warning("⚠️ No continuation ID for upload \(id.uuidString)", category: .ai)
            return nil
        }
        guard let requestIndex = pendingUploadRequests.firstIndex(where: { $0.id == id }) else {
            Logger.warning("⚠️ No pending request for upload \(id.uuidString)", category: .ai)
            return nil
        }

        let request = pendingUploadRequests[requestIndex]
        pendingUploadRequests.remove(at: requestIndex)
        uploadContinuationIds.removeValue(forKey: id)
        let uploadStart = Date()
        Logger.info(
            "📤 Upload handling started",
            category: .diagnostics,
            metadata: [
                "request_id": id.uuidString,
                "kind": request.kind.rawValue,
                "file_count": "\(fileURLs.count)",
                "title": request.metadata.title
            ]
        )

        let shouldReportProgress = request.kind == .resume
        if shouldReportProgress && !fileURLs.isEmpty {
            await extractionProgressHandler?(ExtractionProgressUpdate(
                stage: .fileAnalysis,
                state: .active,
                detail: request.metadata.title
            ))
        }

        // Track uploaded items
        if !fileURLs.isEmpty {
            let newItems = fileURLs.map {
                OnboardingUploadedItem(
                    id: UUID(),
                    filename: $0.lastPathComponent,
                    url: $0,
                    uploadedAt: Date()
                )
            }
            uploadedItems.append(contentsOf: newItems)
        }

        var processed: [OnboardingProcessedUpload] = []
        var payload = JSON()
        payload["kind"].string = request.kind.rawValue

        if let target = request.metadata.targetKey {
            payload["targetKey"].string = target
        }

        var metadata = JSON()
        metadata["title"].string = request.metadata.title
        metadata["allow_multiple"].bool = request.metadata.allowMultiple
        metadata["allow_url"].bool = request.metadata.allowURL
        if let cancelMessage = request.metadata.cancelMessage {
            metadata["cancel_message"].string = cancelMessage
        }
        payload["metadata"] = metadata

        do {
            if fileURLs.isEmpty {
                if let cancelReason = cancelReason {
                    payload["status"].string = "cancelled"
                    let trimmed = cancelReason.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        payload["cancel_reason"].string = trimmed
                    }
                } else {
                    payload["status"].string = "skipped"
                }
            } else {
                // Process files through storage
                processed = try fileURLs.map { try uploadStorage.processFile(at: $0) }

                var filesJSON: [JSON] = []
                for item in processed {
                    var json = item.toJSON()
                    if let originalURL {
                        json["source"].string = "url"
                        json["original_url"].string = originalURL.absoluteString
                    }
                    filesJSON.append(json)
                }

                payload["status"].string = "uploaded"
                payload["files"] = JSON(filesJSON)

                // Emit generic upload completed event
                let uploadInfos = processed.map { item in
                    ProcessedUploadInfo(
                        storageURL: item.storageURL,
                        contentType: item.contentType,
                        filename: item.storageURL.lastPathComponent
                    )
                }

                // Build metadata from request
                var uploadMetadata = JSON()
                uploadMetadata["title"].string = request.metadata.title
                uploadMetadata["instructions"].string = request.metadata.instructions
                if let targetKey = request.metadata.targetKey {
                    uploadMetadata["target_key"].string = targetKey
                }

                // Emit generic upload completed event (downstream handlers will process based on file type)
                await eventBus.publish(.uploadCompleted(
                    files: uploadInfos,
                    requestKind: request.kind.rawValue,
                    callId: continuationId.uuidString,
                    metadata: uploadMetadata
                ))

                // Handle targeted uploads (e.g., basics.image)
                if let target = request.metadata.targetKey {
                    try await handleTargetedUpload(target: target, processed: processed)
                    payload["updates"] = JSON([target])
                }
            }

            if shouldReportProgress && !fileURLs.isEmpty {
                await extractionProgressHandler?(ExtractionProgressUpdate(
                    stage: .fileAnalysis,
                    state: .completed,
                    detail: request.metadata.title
                ))
            }
        } catch {
            payload["status"].string = "failed"
            payload["error"].string = error.localizedDescription

            if shouldReportProgress && !fileURLs.isEmpty {
                await extractionProgressHandler?(ExtractionProgressUpdate(
                    stage: .fileAnalysis,
                    state: .failed,
                    detail: error.localizedDescription
                ))
            }

            // Cleanup processed files on error
            for item in processed {
                uploadStorage.removeFile(at: item.storageURL)
            }
        }

        let status = payload["status"].stringValue
        switch status {
        case "uploaded":
            Logger.info("✅ Upload completed successfully", category: .ai)
        case "skipped":
            Logger.info("⚠️ Upload skipped by user", category: .ai)
        case "cancelled":
            Logger.info("⚠️ Upload cancelled by assistant", category: .ai, metadata: [
                "reason": payload["cancel_reason"].stringValue
            ])
        case "failed":
            let errorDescription = payload["error"].stringValue
            Logger.error("❌ Upload failed during processing: \(errorDescription)", category: .ai)
        default:
            Logger.warning("⚠️ Upload completion returned status: \(status)", category: .ai)
        }
        let totalMs = Int(Date().timeIntervalSince(uploadStart) * 1000)
        Logger.info(
            "📤 Upload handling finished",
            category: .diagnostics,
            metadata: [
                "request_id": id.uuidString,
                "status": status,
                "duration_ms": "\(totalMs)"
            ]
        )
        return (continuationId, payload)
    }

    private func resumeUpload(id: UUID, withError message: String) async -> (continuationId: UUID, payload: JSON)? {
        guard let continuationId = uploadContinuationIds[id] else { return nil }

        removeUploadRequest(id: id)
        uploadContinuationIds.removeValue(forKey: id)

        var payload = JSON()
        payload["status"].string = "failed"
        payload["error"].string = message

        Logger.error("❌ Upload failed: \(message)", category: .ai)
        return (continuationId, payload)
    }

    private func handleTargetedUpload(target: String, processed: [OnboardingProcessedUpload]) async throws {
        switch target {
        case "basics.image":
            guard let first = processed.first else {
                throw ToolError.executionFailed("No file received for basics.image")
            }
            let data = try Data(contentsOf: first.storageURL)
            try uploadFileService.validateImageData(data: data, fileExtension: first.storageURL.pathExtension)

            // Store image in applicant profile
            let profile = applicantProfileStore.currentProfile()
            profile.pictureData = data
            profile.pictureMimeType = first.contentType
            applicantProfileStore.save(profile)

            Logger.debug("📸 Applicant profile image updated (\(data.count) bytes, mime: \(first.contentType ?? "unknown"))", category: .ai)

        default:
            throw ToolError.invalidParameters("Unsupported target_key: \(target)")
        }
    }

    private func removeUploadRequest(id: UUID) {
        pendingUploadRequests.removeAll { $0.id == id }
    }

    // MARK: - Lifecycle

    /// Clears all pending uploads and continuation state (for interview reset).
    func reset() {
        pendingUploadRequests.removeAll()
        uploadContinuationIds.removeAll()
        uploadedItems.removeAll()
    }
}
