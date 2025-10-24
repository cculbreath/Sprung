# PDF Extraction Specification for Onboarding Interview

**Status:** Planned for M2
**Date:** 2025-10-24
**Dependencies:** OpenRouter integration, Gemini 2.0 Flash model access

## Overview

Resume PDF extraction is a critical component of the onboarding interview's Phase 1 (Core Facts Collection). The current implementation uses naive local text extraction which fails for:
- Scanned/image-based PDFs (no OCR)
- Complex layouts (multi-column, tables)
- Mathematical notation and symbols
- Binary PDF formats

This specification defines a robust PDF extraction workflow using OpenRouter + Gemini 2.0 Flash for multimodal document processing.

---

## Problem Statement

### Current Implementation Limitations

**File:** `Sprung/Onboarding/Tools/Implementations/GetUserUploadTool.swift:256-273`

```swift
private func extractText(from url: URL) -> String? {
    // Naive UTF-8 decode - returns garbage for binary PDFs
    return try? String(contentsOf: url, encoding: .utf8)
}
```

**Issues:**
1. **No OCR support** - Scanned PDFs return empty/garbage text
2. **Layout destruction** - Multi-column resumes become garbled
3. **Missing visual data** - Tables, charts, formatting lost
4. **Token waste** - If sent to OpenAI's vision API, charges 3-8x more than necessary

---

## Architecture Overview

### High-Level Flow

```
┌─────────────────┐
│ User uploads    │
│ resume PDF      │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ GetUserUploadTool                   │
│ - Stores PDF to disk                │
│ - NO local text extraction          │
│ - Returns file path + metadata      │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ InterviewOrchestrator               │
│ collectSkeletonTimeline()           │
│ - Reads pdfExtractionModelId from   │
│   AppStorage                        │
│ - Converts PDF to base64            │
│ - Sends to OpenRouter               │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ OpenRouter + Gemini 2.0 Flash       │
│ - Native PDF processing             │
│ - OCR for scanned pages             │
│ - Preserves layout/tables           │
│ - Returns structured JSON timeline  │
└────────┬────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────┐
│ User validates timeline             │
│ via submit_for_validation tool      │
└─────────────────────────────────────┘
```

---

## Settings Integration

### User-Configurable PDF Extraction Model

**File:** `Sprung/App/Views/SettingsView.swift:9,59,154-175`

#### AppStorage Key
```swift
@AppStorage("onboardingPDFExtractionModelId")
private var pdfExtractionModelId: String = "google/gemini-2.0-flash"
```

#### UI Component
- **Location:** Settings → Onboarding Interview section
- **Control:** Dropdown picker showing all enabled OpenRouter models
- **Default:** `google/gemini-2.0-flash` (sorted to top)
- **Description:** "Model used to extract structured data from resume PDFs. Gemini 2.0 Flash is recommended for cost-effective multimodal extraction."

#### Model Requirements
- **Gemini 2.0 Flash** added to `EnabledLLMStore` default seeds
- **Always enabled** - checkbox disabled in OpenRouter model selection UI
- All other enabled OpenRouter models available as alternatives

---

## Implementation Requirements

### 1. GetUserUploadTool Modifications

**File:** `Sprung/Onboarding/Tools/Implementations/GetUserUploadTool.swift`

#### Remove Local Text Extraction
```swift
// REMOVE THIS:
private func extractText(from url: URL) -> String? {
    return try? String(contentsOf: url, encoding: .utf8)
}

// UPDATE processFile to NOT extract text:
func processFile(at sourceURL: URL) throws -> ProcessedUpload {
    // ... copy file logic ...

    return ProcessedUpload(
        id: identifier,
        filename: sourceURL.lastPathComponent,
        storageURL: destinationURL,
        extractedText: ""  // Always empty - extraction happens in orchestrator
    )
}
```

---

### 2. InterviewOrchestrator Integration

**File:** `Sprung/Onboarding/Core/InterviewOrchestrator.swift`

#### Add OpenRouter Client Dependency

```swift
actor InterviewOrchestrator {
    private let client: OpenAIService
    private let openRouterClient: OpenAIService?  // NEW: For PDF extraction
    private let pdfExtractionModelId: String       // NEW: From AppStorage

    init(
        client: OpenAIService,
        openRouterClient: OpenAIService?,          // NEW
        pdfExtractionModelId: String,              // NEW
        state: InterviewState,
        toolExecutor: ToolExecutor,
        checkpoints: Checkpoints,
        callbacks: Callbacks,
        systemPrompt: String
    ) {
        self.client = client
        self.openRouterClient = openRouterClient
        self.pdfExtractionModelId = pdfExtractionModelId
        // ... rest of init
    }
}
```

#### Update collectSkeletonTimeline

```swift
private func collectSkeletonTimeline() async throws -> JSON {
    await callbacks.emitAssistantMessage("📄 Please upload your resume.")

    var uploadArgs = JSON()
    uploadArgs["uploadType"].string = "resume"
    uploadArgs["prompt"].string = "Upload your latest resume to extract a skeleton timeline."

    let uploadResult = try await callTool(name: "get_user_upload", arguments: uploadArgs)
    guard uploadResult["status"].stringValue == "uploaded",
          let firstUpload = uploadResult["uploads"].array?.first,
          let storageURLString = firstUpload["storageUrl"].string,
          let storageURL = URL(string: storageURLString) else {
        throw ToolError.userCancelled
    }

    // NEW: Extract timeline from PDF using OpenRouter
    let timeline = try await extractTimelineFromPDF(fileURL: storageURL)

    var validationArgs = JSON()
    validationArgs["dataType"].string = "experience"
    validationArgs["data"] = timeline
    validationArgs["message"].string = "Review the generated skeleton timeline."

    let validation = try await callTool(name: "submit_for_validation", arguments: validationArgs)
    let status = validation["status"].stringValue
    guard status != "rejected" else {
        throw ToolError.executionFailed("Skeleton timeline rejected.")
    }

    let data = validation["data"]
    let final = data != .null ? data : timeline
    await callbacks.storeSkeletonTimeline(final)
    return final
}
```

#### Add PDF Extraction Method

```swift
private func extractTimelineFromPDF(fileURL: URL) async throws -> JSON {
    guard let openRouterClient = openRouterClient else {
        throw ToolError.executionFailed("OpenRouter client not configured for PDF extraction")
    }

    // Convert PDF to base64
    guard let pdfData = try? Data(contentsOf: fileURL) else {
        throw ToolError.executionFailed("Failed to read PDF file")
    }
    let base64PDF = pdfData.base64EncodedString()

    // Construct OpenRouter request with PDF
    let message = InputMessage(
        role: "user",
        content: .array([
            .file(.init(
                type: "application/pdf",
                url: "data:application/pdf;base64,\(base64PDF)"
            )),
            .text(buildTimelineExtractionPrompt())
        ])
    )

    var parameters = ModelResponseParameter(
        input: .array([.message(message)]),
        model: .custom(pdfExtractionModelId),
        temperature: 0.0,
        text: TextConfiguration(format: .jsonObject)
    )

    let response = try await openRouterClient.responseCreate(parameters)
    guard let output = response.outputText,
          let data = output.data(using: .utf8) else {
        throw ToolError.executionFailed("Timeline extraction failed")
    }

    return try JSON(data: data)
}

private func buildTimelineExtractionPrompt() -> String {
    """
    Extract a chronological career timeline from this resume PDF.

    Return a JSON object with this exact structure:
    {
      "experiences": [
        {
          "title": "Job Title",
          "organization": "Company Name",
          "start": "YYYY-MM",
          "end": "YYYY-MM" or null,
          "summary": "Brief description"
        }
      ]
    }

    Instructions:
    - Use ISO 8601 date format (YYYY-MM) for dates
    - Use null for missing or current positions (end date)
    - Focus on professional experience, not education or skills
    - Preserve original formatting insights (e.g., table structure)
    - Extract ALL listed positions, maintaining chronological order
    """
}
```

---

### 3. OnboardingInterviewService Updates

**File:** `Sprung/Onboarding/Core/OnboardingInterviewService.swift`

#### Add OpenRouter Dependencies

```swift
@MainActor
@Observable
final class OnboardingInterviewService {
    private let openAIService: OpenAIService?
    private let openRouterService: OpenRouterService?    // NEW
    private let applicantProfileStore: ApplicantProfileStore

    @AppStorage("onboardingPDFExtractionModelId")
    private var pdfExtractionModelId: String = "google/gemini-2.0-flash"  // NEW

    init(
        openAIService: OpenAIService?,
        openRouterService: OpenRouterService?,           // NEW
        applicantProfileStore: ApplicantProfileStore,
        modelContext: ModelContext
    ) {
        self.openAIService = openAIService
        self.openRouterService = openRouterService       // NEW
        self.applicantProfileStore = applicantProfileStore
        // ... rest of init
    }
}
```

#### Update Orchestrator Initialization

```swift
private func createOrchestrator(using service: OpenAIService) -> InterviewOrchestrator {
    // Create OpenRouter client if available
    var openRouterClient: OpenAIService? = nil
    if let apiKey = UserDefaults.standard.string(forKey: "openRouterAPIKey"),
       !apiKey.isEmpty {
        openRouterClient = OpenAIServiceFactory.service(
            apiKey: apiKey,
            overrideBaseURL: "https://openrouter.ai/api/v1"
        )
    }

    return InterviewOrchestrator(
        client: service,
        openRouterClient: openRouterClient,              // NEW
        pdfExtractionModelId: pdfExtractionModelId,      // NEW
        state: interviewState,
        toolExecutor: toolExecutor,
        checkpoints: checkpoints,
        callbacks: callbacks,
        systemPrompt: systemPrompt
    )
}
```

---

## Cost Analysis & User Approval

### Token Consumption Estimates

| Document Type | Pages | Gemini 2.0 Flash Tokens | Cost (approx) |
|---------------|-------|-------------------------|---------------|
| Typical Resume | 1-2 | ~2,000-4,000 | $0.0001-0.0003 |
| Academic CV | 3-5 | ~6,000-10,000 | $0.0005-0.0008 |
| Extended Resume | 6-10 | ~12,000-20,000 | $0.0009-0.0015 |

**Gemini 2.0 Flash Pricing:** $0.075 per 1M input tokens

### User Approval Workflow

For resumes > 10 pages, prompt user with cost estimate:

```swift
if pageCount > 10 {
    let estimatedTokens = pageCount * 2000
    let estimatedCost = (Double(estimatedTokens) / 1_000_000) * 0.075

    let message = """
    This \(pageCount)-page document will cost approximately $\(String(format: "%.3f", estimatedCost))
    to process with Gemini 2.0 Flash.

    Continue with PDF extraction?
    """

    // Use get_user_option tool for approval
    // ...
}
```

---

## Error Handling

### Fallback Strategy

```swift
private func extractTimelineFromPDF(fileURL: URL) async throws -> JSON {
    // Attempt 1: OpenRouter + configured model
    do {
        return try await extractViaOpenRouter(fileURL: fileURL, modelId: pdfExtractionModelId)
    } catch {
        await callbacks.emitAssistantMessage("⚠️ PDF extraction failed with \(pdfExtractionModelId). Trying fallback...")

        // Attempt 2: Fallback to Claude 3.5 Sonnet (premium quality)
        if let fallbackResult = try? await extractViaOpenRouter(
            fileURL: fileURL,
            modelId: "anthropic/claude-sonnet-4.5"
        ) {
            return fallbackResult
        }

        // Attempt 3: Last resort - naive text extraction
        await callbacks.emitAssistantMessage("⚠️ Multimodal extraction unavailable. Using basic text extraction.")
        return try await extractViaLocalText(fileURL: fileURL)
    }
}
```

### Common Failure Modes

| Error | Cause | Resolution |
|-------|-------|------------|
| `OpenRouter client not configured` | Missing API key | Prompt user to add OpenRouter key in Settings |
| `Failed to read PDF file` | File permissions / corruption | Ask user to re-upload |
| `Timeline extraction failed` | Model timeout / API error | Retry with fallback model |
| `Model \(id) not found` | Invalid model ID | Reset to default (Gemini 2.0 Flash) |

---

## Testing Requirements

### Unit Tests

1. **PDF Base64 Encoding**
   - Test various PDF sizes (1KB - 10MB)
   - Verify base64 output correctness

2. **OpenRouter Client Creation**
   - Test with valid/invalid API keys
   - Verify base URL override

3. **Timeline Extraction Prompt**
   - Validate JSON schema structure
   - Test with sample resumes

### Integration Tests

1. **End-to-End Extraction**
   - Upload test resume PDFs (text-based, scanned, multi-column)
   - Verify correct timeline structure returned
   - Validate all positions extracted

2. **Model Selection**
   - Test with different pdfExtractionModelId values
   - Verify correct model used in API calls

3. **Error Recovery**
   - Simulate OpenRouter unavailable
   - Verify fallback to local extraction
   - Test user-facing error messages

### Manual QA Checklist

- [ ] Settings UI displays PDF extraction model picker
- [ ] Gemini 2.0 Flash appears first in dropdown
- [ ] Changing model persists across app restarts
- [ ] Resume upload triggers OpenRouter extraction
- [ ] Extracted timeline matches resume content
- [ ] User can approve/modify/reject timeline
- [ ] Cost warnings appear for large PDFs (>10 pages)
- [ ] Fallback works when OpenRouter unavailable

---

## Migration Notes

### Breaking Changes

**From M0/M1 to M2:**
- `GetUserUploadTool` no longer returns `extractedText`
- `InterviewOrchestrator.init()` signature changes (new parameters)
- `OnboardingInterviewService` requires `OpenRouterService` dependency

### Data Migration

**No data migration required.** Existing checkpoints store `skeletonTimeline` as JSON, which remains unchanged.

### Backwards Compatibility

For users without OpenRouter API keys:
- PDF extraction falls back to local text extraction (current behavior)
- Warning message displayed: "For best results, add an OpenRouter API key in Settings"

---

## Future Enhancements (Post-M2)

1. **Parallel Model Extraction**
   - Extract with multiple models (Gemini + Claude)
   - Present best/merged result to user

2. **Caching & Incremental Extraction**
   - Store PDF hash + extracted timeline
   - Skip re-extraction if PDF unchanged

3. **Visual Element Extraction**
   - Extract charts/graphs as separate artifacts
   - Store portfolio images from resumes

4. **Batch Processing**
   - Allow multiple file uploads
   - Extract from all PDFs in parallel

---

## Success Criteria

**M2 is complete when:**

✅ PDF extraction uses OpenRouter + Gemini 2.0 Flash by default
✅ Settings UI allows model selection
✅ Scanned PDFs successfully extracted via OCR
✅ Multi-column resumes maintain correct structure
✅ Cost is 80-99% cheaper than OpenAI direct PDF upload
✅ Fallback to local extraction works when OpenRouter unavailable
✅ All M0/M1 functionality preserved

---

## References

- OpenAI PDF API: https://platform.openai.com/docs/guides/pdf-files
- OpenRouter PDF Support: https://openrouter.ai/docs/features/multimodal/pdfs
- Gemini 2.0 Flash Model Card: https://storage.googleapis.com/model-cards/documents/gemini-2-flash.pdf
- SwiftOpenAI Library: https://github.com/jamesrochabrun/SwiftOpenAI

---

**Document Version:** 1.0
**Last Updated:** 2025-10-24
**Author:** Claude Code
**Status:** Ready for Review
