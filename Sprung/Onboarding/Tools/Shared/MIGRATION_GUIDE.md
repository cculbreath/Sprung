# Migration Guide: Using Shared Tool Infrastructure

This guide shows how to refactor existing tools to use the shared helper utilities.

## Before and After Examples

### Example 1: CreateTimelineCardTool

**Before (current implementation):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    guard let fields = params["fields"].dictionary else {
        throw ToolError.invalidParameters("fields must be provided")
    }
    // Normalize fields for Phase 1 skeleton timeline constraints
    let normalizedFields = TimelineCardSchema.normalizePhaseOneFields(JSON(fields), includeExperienceType: true)
    // Create timeline card via coordinator (which emits events)
    let result = await coordinator.createTimelineCard(fields: normalizedFields)
    return .immediate(result)
}
```

**After (with shared helpers):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    // Use ToolResultHelpers for validation
    let fieldsDict = try ToolResultHelpers.requireObject(params["fields"].dictionary, named: "fields")
    let fieldsJSON = JSON(fieldsDict)

    // Use TimelineValidation for field validation
    try TimelineValidation.validateNewCardFields(fieldsJSON)

    // Normalize fields for Phase 1 skeleton timeline constraints
    let normalizedFields = TimelineCardSchema.normalizePhaseOneFields(fieldsJSON, includeExperienceType: true)

    // Create timeline card via coordinator (which emits events)
    let result = await coordinator.createTimelineCard(fields: normalizedFields)
    return .immediate(result)
}
```

**Benefits:**
- Explicit validation of required fields before processing
- Consistent error messages across all tools
- Clearer intent through named validation functions

### Example 2: UpdateTimelineCardTool

**Before (current implementation):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    guard let id = params["id"].string, !id.isEmpty else {
        throw ToolError.invalidParameters("id must be provided")
    }
    guard let fields = params["fields"].dictionary else {
        throw ToolError.invalidParameters("fields must be provided")
    }
    // Normalize fields for Phase 1 skeleton timeline constraints (don't override experience_type on update)
    let normalizedFields = TimelineCardSchema.normalizePhaseOneFields(JSON(fields), includeExperienceType: false)
    // Update timeline card via coordinator (which emits events)
    let result = await coordinator.updateTimelineCard(id: id, fields: normalizedFields)
    return .immediate(result)
}
```

**After (with shared helpers):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    // Use TimelineValidation for ID validation
    let id = try ToolResultHelpers.requireString(params["id"].string, named: "id")

    // Use ToolResultHelpers for field validation
    let fieldsDict = try ToolResultHelpers.requireObject(params["fields"].dictionary, named: "fields")
    let fieldsJSON = JSON(fieldsDict)

    // Validate at least one field is being updated
    try TimelineValidation.validateUpdateFields(fieldsJSON)

    // Normalize fields for Phase 1 skeleton timeline constraints (don't override experience_type on update)
    let normalizedFields = TimelineCardSchema.normalizePhaseOneFields(fieldsJSON, includeExperienceType: false)

    // Update timeline card via coordinator (which emits events)
    let result = await coordinator.updateTimelineCard(id: id, fields: normalizedFields)
    return .immediate(result)
}
```

**Benefits:**
- Validates that update actually has fields to update
- Consistent validation across create and update operations
- Better error messages for missing or invalid parameters

### Example 3: DeleteTimelineCardTool

**Before (current implementation):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    guard let id = params["id"].string, !id.isEmpty else {
        throw ToolError.invalidParameters("id must be provided")
    }
    // Delete timeline card via coordinator (which emits events)
    let result = await coordinator.deleteTimelineCard(id: id)
    return .immediate(result)
}
```

**After (with shared helpers):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    // Use TimelineValidation for ID validation
    let id = try ToolResultHelpers.requireString(params["id"].string, named: "id")

    // Delete timeline card via coordinator (which emits events)
    let result = await coordinator.deleteTimelineCard(id: id)
    return .immediate(result)
}
```

**Benefits:**
- Consistent validation logic
- Same error message format as other tools
- Less code duplication

### Example 4: ReorderTimelineCardsTool

**Before (hypothetical without helpers):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    guard let orderedIds = params["ordered_ids"].arrayObject as? [String] else {
        throw ToolError.invalidParameters("ordered_ids must be an array of strings")
    }
    guard !orderedIds.isEmpty else {
        throw ToolError.invalidParameters("ordered_ids cannot be empty")
    }

    let result = await coordinator.reorderTimelineCards(orderedIds: orderedIds)
    return .immediate(result)
}
```

**After (with shared helpers):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    guard let orderedIds = params["ordered_ids"].arrayObject as? [String] else {
        throw ToolError.invalidParameters("ordered_ids must be an array of strings")
    }

    // Use TimelineValidation
    try TimelineValidation.validateOrderedIds(orderedIds)

    let result = await coordinator.reorderTimelineCards(orderedIds: orderedIds)
    return .immediate(result)
}
```

**Benefits:**
- Centralized validation of ordered IDs
- Consistent error handling

### Example 5: Tool with Custom Response Building

**Before (hypothetical):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    let artifacts = await coordinator.listArtifactSummaries()

    var response = JSON()
    response["success"].bool = true
    response["items"].arrayObject = artifacts.map { $0.object }
    response["count"].int = artifacts.count
    response["total"].int = artifacts.count

    return .immediate(response)
}
```

**After (with shared helpers):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    let artifacts = await coordinator.listArtifactSummaries()
    return ToolResultHelpers.listResponse(items: artifacts)
}
```

**Benefits:**
- Much less code
- Consistent response format across all list operations
- Automatic inclusion of count field

### Example 6: Tool with Complex Validation

**Before (hypothetical):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    guard let cardType = params["type"].string else {
        throw ToolError.invalidParameters("type is required")
    }

    let validTypes = ["work", "education", "volunteer", "project"]
    guard validTypes.contains(cardType) else {
        throw ToolError.invalidParameters(
            "type must be one of: work, education, volunteer, project. Got: '\(cardType)'"
        )
    }

    guard let content = params["content"].string else {
        throw ToolError.invalidParameters("content is required")
    }

    guard content.count >= 100 else {
        throw ToolError.invalidParameters(
            "content must be at least 100 characters. Got: \(content.count)"
        )
    }

    // ... process ...
}
```

**After (with shared helpers):**
```swift
func execute(_ params: JSON) async throws -> ToolResult {
    let cardType = try ToolResultHelpers.requireString(params["type"].string, named: "type")

    let validTypes = ["work", "education", "volunteer", "project"]
    guard validTypes.contains(cardType) else {
        throw ToolError.invalidEnum(field: "type", value: cardType, validValues: validTypes)
    }

    let content = try ToolResultHelpers.requireString(params["content"].string, named: "content")

    guard content.count >= 100 else {
        throw ToolError.tooShort(field: "content", minLength: 100, actualLength: content.count)
    }

    // ... process ...
}
```

**Benefits:**
- Consistent error message formatting
- Reusable validation patterns
- Better error messages for users

## Migration Strategy

### Phase 1: Add Validation (Non-Breaking)
Add validation helpers without changing existing logic:
```swift
// Before coordinator call, add validation
try TimelineValidation.validateCardId(id)
let result = await coordinator.createTimelineCard(...)
```

### Phase 2: Standardize Parameter Extraction
Replace guard statements with helper functions:
```swift
// Replace this:
guard let id = params["id"].string, !id.isEmpty else {
    throw ToolError.invalidParameters("id must be provided")
}

// With this:
let id = try ToolResultHelpers.requireString(params["id"].string, named: "id")
```

### Phase 3: Standardize Responses
Use response builders where applicable:
```swift
// For list operations
return ToolResultHelpers.listResponse(items: items)

// For status operations
return ToolResultHelpers.statusResponse(status: "completed", message: "Done")
```

## Best Practices

1. **Validate Early** - Use helpers at the start of execute() to fail fast
2. **Use Descriptive Names** - Named parameters make validation errors clearer
3. **Combine Helpers** - Use both Timeline and ToolResult helpers together
4. **Keep It Simple** - Don't over-engineer; use helpers where they add value
5. **Test Thoroughly** - Ensure validation catches all edge cases

## When NOT to Use Helpers

Avoid using helpers when:
- Tool has unique validation requirements not covered by helpers
- Response format is tool-specific and shouldn't be standardized
- Adding a helper would make code less readable
- Performance is critical and helpers add overhead (rare)

## Adding New Helpers

When you find repeated patterns in multiple tools:

1. **Extract to Helper** - Create new helper function in appropriate file
2. **Document Usage** - Add example to README
3. **Add Tests** - Verify helper works correctly (when test infrastructure exists)
4. **Update This Guide** - Add migration example

Example:
```swift
// New helper in TimelineValidation
static func validateDateRange(start: String?, end: String?) throws {
    guard let start = start, !start.isEmpty else {
        throw ToolError.invalidParameters("Start date is required")
    }

    if let end = end, !end.isEmpty, end.lowercased() != "present" {
        // Could add date parsing logic here to validate end > start
    }
}
```

## Questions?

If you're unsure whether to use a helper:
1. Check if the pattern appears in 2+ tools
2. See if it makes the code more readable
3. Consider if it helps maintain consistency

When in doubt, start simple and add helpers as patterns emerge.
