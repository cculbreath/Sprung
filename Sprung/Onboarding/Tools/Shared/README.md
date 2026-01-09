# Shared Tool Infrastructure

This directory contains shared utilities for onboarding interview tools.

## Files

### TimelineToolHelpers.swift

Provides common validation, response building, and data processing utilities for timeline card operations.

**Key Components:**

1. **TimelineValidation** - Validation helpers for timeline operations
   - `validateCardId(_:)` - Ensures card ID is present and non-empty
   - `validateNewCardFields(_:)` - Validates required fields for card creation
   - `validateUpdateFields(_:)` - Validates update has at least one field
   - `validateOrderedIds(_:)` - Validates reorder operations

2. **TimelineResponseBuilder** - Standard response builders
   - `createSuccessResponse(id:fields:)` - Response for card creation
   - `updateSuccessResponse(id:fields:)` - Response for card updates
   - `deleteSuccessResponse(id:)` - Response for card deletion
   - `reorderSuccessResponse(orderedIds:)` - Response for reordering

3. **TimelineDataProcessor** - Data processing utilities
   - `extractExperienceType(_:)` - Extracts experience type with default
   - `normalizeDate(_:)` - Normalizes date strings
   - `hasMinimumFields(_:)` - Validates card has minimum required fields
   - `countCards(in:)` - Counts cards in timeline JSON

**Usage Example:**

```swift
// In CreateTimelineCardTool
func execute(_ params: JSON) async throws -> ToolResult {
    guard let fields = params["fields"].dictionary else {
        throw ToolError.invalidParameters("fields must be provided")
    }

    let fieldsJSON = JSON(fields)

    // Validate using shared helper
    try TimelineValidation.validateNewCardFields(fieldsJSON)

    // Normalize and create
    let normalizedFields = TimelineCardSchema.normalizePhaseOneFields(fieldsJSON, includeExperienceType: true)
    let result = await coordinator.createTimelineCard(fields: normalizedFields)

    return .immediate(result)
}
```

### ToolResultHelpers.swift

Provides convenience methods for creating consistent tool results and parameter validation.

**Key Components:**

1. **ToolResultHelpers.success** - Success response builders
   - `success(message:)` - Simple success with optional message
   - `success(data:)` - Success with custom data
   - `success(key:value:)` - Success with single key-value pair
   - `listResponse(items:)` - Response with array of items
   - `paginatedResponse(items:total:offset:limit:)` - Paginated list response
   - `statusResponse(status:message:additionalData:)` - Status-based response

2. **ToolResultHelpers.error** - Error response builders
   - `invalidParameters(_:)` - Invalid parameter errors
   - `executionFailed(_:)` - Execution failure errors
   - `missingRequiredFields(_:)` - Missing field errors

3. **ToolResultHelpers validation** - Parameter validation
   - `requireString(_:named:)` - Validates required string parameter
   - `requireNonEmptyArray(_:named:)` - Validates required non-empty array
   - `requireObject(_:named:)` - Validates required object parameter

4. **ToolError extensions** - Common error patterns
   - `missingField(_:)` - Error for missing field
   - `invalidEnum(field:value:validValues:)` - Error for invalid enum value
   - `tooShort(field:minLength:actualLength:)` - Error for too-short value

**Usage Examples:**

```swift
// Simple success response
func execute(_ params: JSON) async throws -> ToolResult {
    // ... do work ...
    return ToolResultHelpers.success(message: "Operation completed")
}

// Success with data
func execute(_ params: JSON) async throws -> ToolResult {
    var response = JSON()
    response["id"].string = "123"
    response["title"].string = "Test"
    return ToolResultHelpers.success(data: response)
}

// Parameter validation
func execute(_ params: JSON) async throws -> ToolResult {
    let title = try ToolResultHelpers.requireString(params["title"].string, named: "title")
    let items = try ToolResultHelpers.requireNonEmptyArray(params["items"].array, named: "items")

    // ... use validated parameters ...
}

// List response
func execute(_ params: JSON) async throws -> ToolResult {
    let items = await fetchItems()
    return ToolResultHelpers.listResponse(items: items)
}

// Custom error
func execute(_ params: JSON) async throws -> ToolResult {
    guard let type = params["type"].string else {
        throw ToolError.missingField("type")
    }

    let validTypes = ["work", "education", "volunteer"]
    guard validTypes.contains(type) else {
        throw ToolError.invalidEnum(field: "type", value: type, validValues: validTypes)
    }

    // ... proceed ...
}
```

## Integration with Existing Architecture

These utilities work within the current tool architecture:

1. **Tools implement `InterviewTool` protocol** - Defined in `ToolProtocol.swift`
2. **Tools hold `unowned` reference to coordinator** - No circular dependency
3. **Tools return `ToolResult`** - Defined as `.immediate(JSON)` or `.error(ToolError)`. UI tools block via `UIToolContinuationManager.awaitUserAction()` until user interaction completes, then return the result in a single API turn.
4. **Coordinator methods delegate to services** - Services emit events for state updates

The shared utilities provide:
- **Consistent validation** - Reduces code duplication across tools
- **Standard response formats** - Makes tool outputs predictable
- **Common error patterns** - Improves error message consistency
- **Data processing helpers** - Simplifies common operations

## Design Principles

1. **Don't Repeat Yourself (DRY)** - Common patterns are extracted to shared utilities
2. **Type Safety** - Use Swift's type system to catch errors at compile time
3. **Descriptive Errors** - Error messages clearly indicate what went wrong
4. **Consistent Responses** - All tools return similarly structured JSON
5. **Minimal Dependencies** - Only depends on Foundation and SwiftyJSON

## Future Enhancements

Consider adding:
- **Schema validation helpers** - Common JSON schema patterns
- **Pagination utilities** - Standardized pagination logic
- **Batch operation helpers** - Support for bulk operations
- **Async validation** - Validation that requires async operations
- **Response templates** - Pre-built response structures for common patterns
