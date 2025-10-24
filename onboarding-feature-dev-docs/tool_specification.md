# **Onboarding Interview \- LLM Tools Specification**

## **Executive Summary**

This document provides a complete specification for all LLM-invocable tools in the onboarding interview system. This is the **single source of truth** for tool architecture. All tools will use the schema-first, dynamic JSON interface.

## **Core Tool Architecture**

### **Tool Execution Flow**

// 1\. LLM calls tool via function calling  
// 2\. App receives tool call in streaming response  
// 3\. Tool executor processes parameters  
// 4\. UI updates (if needed)  
// 5\. Tool returns response to LLM

### **Base Tool Protocol (Canonical)**

This is the **only** protocol to be used. Generic or associatedtype-based protocols are not to be used.  
protocol InterviewTool {  
    var name: String { get }  
    var description: String { get }  
    var parameters: JSONSchema { get }  
      
    func execute(\_ params: JSON) async throws \-\> ToolResult  
}

enum ToolResult {  
    case immediate(JSON)                           // Instant response  
    case waiting(String, ContinuationToken)        // Needs user input  
    case error(ToolError)                         // Execution failed  
}

struct ContinuationToken {  
    let id: UUID  
    let toolName: String  
    let resumeHandler: (JSON) async \-\> ToolResult  
}

// Other related types  
struct JSONSchema: Codable { /\* ... \*/ }  
struct JSON: Codable { /\* ... \*/ }  
enum ToolError: Error {  
    case invalidParameters(String)  
    case executionFailed(String)  
    // ...  
}

## **Tool Catalog**

### **1\. GetUserOption Tool**

**Purpose:** Present multiple choice options to user and collect selection  
**Parameters:**  
{  
  "type": "object",  
  "required": \["prompt", "options"\],  
  "properties": {  
    "prompt": {  
      "type": "string",  
      "description": "Question or instruction for the user"  
    },  
    "options": {  
      "type": "array",  
      "items": {  
        "type": "object",  
        "required": \["id", "label"\],  
        "properties": {  
          "id": {"type": "string"},  
          "label": {"type": "string"},  
          "description": {"type": "string"},  
          "icon": {"type": "string"}  
        }  
      },  
      "minItems": 2,  
      "maxItems": 6  
    },  
    "allowMultiple": {  
      "type": "boolean",  
      "default": false,  
      "description": "Allow selecting multiple options"  
    },  
    "required": {  
      "type": "boolean",  
      "default": true,  
      "description": "Is selection required to continue"  
    }  
  }  
}

**Response:**  
{  
  "selectedIds": \["option1", "option3"\],  
  "timestamp": "2025-10-24T10:30:00Z"  
}

### **2\. SubmitForValidation Tool**

**Purpose:** Display collected data for user review and editing  
**Parameters:**  
{  
  "type": "object",  
  "required": \["dataType", "data"\],  
  "properties": {  
    "dataType": {  
      "type": "string",  
      "enum": \["applicantProfile", "experience", "education", "knowledgeCard"\],  
      "description": "Type of data being validated"  
    },  
    "data": {  
      "type": "object",  
      "description": "The data to validate (structure varies by dataType)"  
    },  
    "message": {  
      "type": "string",  
      "description": "Context message for the user"  
    }  
  }  
}

**Response:**  
{  
  "status": "approved" | "modified" | "rejected",  
  "data": {}, // Updated data if modified  
  "changes": \[  
    {  
      "field": "basics.email",  
      "oldValue": "old@email.com",  
      "newValue": "new@email.com"  
    }  
  \],  
  "userNotes": "Optional user comments"  
}

### **3\. GetUserUpload Tool**

**Purpose:** Request and process file uploads from user  
**Parameters:**  
{  
  "type": "object",  
  "required": \["uploadType"\],  
  "properties": {  
    "uploadType": {  
      "type": "string",  
      "enum": \["resume", "coverletter", "portfolio", "transcript", "certificate", "other"\],  
      "description": "Expected file type"  
    },  
    "prompt": {  
      "type": "string",  
      "description": "Instructions for the user"  
    },  
    "acceptedFormats": {  
      "type": "array",  
      "items": {"type": "string"},  
      "default": \["pdf", "docx", "txt", "md"\],  
      "description": "Allowed file extensions"  
    }  
  }  
}

**Response:**
{
  "uploads": \[
    {
      "id": "upload\_abc123",
      "filename": "resume.pdf",
      "storageUrl": "file:///artifacts/abc123.pdf",
      "extractedText": ""  // DEPRECATED in M2: Text extraction moved to OpenRouter PDF processing
    }
  \],
  "status": "uploaded" | "skipped"
}

**Note:** The `extractedText` field is deprecated as of M2. PDF text extraction now occurs in `InterviewOrchestrator` using OpenRouter + Gemini 2.0 Flash for superior multimodal processing (OCR support, layout preservation, table extraction). See `pdf_extraction_specification.md` for details.

### **4\. GetImageFromUser Tool**

**Purpose:** Collect image uploads (profile photo, certificates, etc.)  
**Parameters:**  
{  
  "type": "object",  
  "required": \["imageType"\],  
  "properties": {  
    "imageType": {  
      "type": "string",  
      "enum": \["profile", "certificate", "portfolio", "other"\],  
      "description": "Purpose of the image"  
    },  
    "prompt": {  
      "type": "string",  
      "description": "Instructions for the user"  
    }  
  }  
}

**Response:**  
{  
  "image": {  
    "id": "img\_xyz789",  
    "storageUrl": "file:///images/xyz789.jpg"  
  },  
  "status": "uploaded" | "skipped"  
}

### **5\. Auth-Dependent Tool Policy**

Auth-dependent functionality is **out of scope** for v1. Do not mock, guess, or partially wire. Before any code is written, create a short design brief covering: required scopes, token storage (Keychain), rate-limit strategy, and failure UX. Until then, tools like query\_github\_repo or fetch\_url must return a user-visible “not configured” error.  
**Example Stub:**  
struct QueryGitHubRepoTool: InterviewTool {  
    var name: String { "query\_github\_repo" }  
    var description: String { "Analyze GitHub repositories for code evidence" }  
    var parameters: JSONSchema { /\* ... schema ... \*/ }

    func execute(\_ params: JSON) async throws \-\> ToolResult {  
        return .error(.executionFailed("GitHub analysis is not configured. Please skip for now."))  
    }  
}

### **6\. FetchURL Tool**

**Purpose:** Retrieve and process content from URLs  
**Parameters:**  
{  
  "type": "object",  
  "required": \["url"\],  
  "properties": {  
    "url": {  
      "type": "string",  
      "format": "uri",  
      "description": "URL to fetch"  
    }  
  }  
}

**Response:**  
{  
  "url": "\[https://linkedin.com/in/johndoe\](https://linkedin.com/in/johndoe)",  
  "extractedData": {  
    "title": "John Doe \- Software Engineer",  
    "text": "Full extracted text..."  
  }  
}

**Implementation Note:** This tool MUST return the "not configured" error as per the policy above until auth/design is complete.

### **7\. GetMacOSContactCard Tool**

**Purpose:** Import user's contact information from macOS Contacts  
**Parameters:**  
{  
  "type": "object",  
  "properties": {  
    "cardType": {  
      "type": "string",  
      "enum": \["me", "specific"\],  
      "default": "me",  
      "description": "Which contact card to fetch"  
    }  
  }  
}

**Response:**  
{  
  "contact": {  
    "name": { "given": "John", "family": "Doe" },  
    "email": \[ {"label": "work", "value": "john@techcorp.com"} \],  
    "phone": \[ {"label": "mobile", "value": "+1-555-0123"} \],  
    "organization": "TechCorp",  
    "jobTitle": "Senior Software Engineer"  
  },  
  "status": "fetched" | "permission\_denied" | "not\_found"  
}

**Implementation:**  
import Contacts

enum ContactError: Error { case denied, other(Error) }

// Wraps the callback-based API in a modern async function  
func requestContactsAccess() async throws {  
    try await withCheckedThrowingContinuation { cont in  
        CNContactStore().requestAccess(for: .contacts) { ok, err in  
            if let err \= err {  
                cont.resume(throwing: ContactError.other(err))  
            } else {  
                ok ? cont.resume() : cont.resume(throwing: ContactError.denied)  
            }  
        }  
    }  
}

// Main fetch logic  
func fetchMeCard() async throws \-\> CNContact {  
    // 1\. Request access using the async wrapper  
    try await requestContactsAccess()  
      
    // 2\. Access is granted, proceed to fetch  
    let store \= CNContactStore()  
    let keys: \[CNKeyDescriptor\] \= \[  
        CNContactGivenNameKey as CNKeyDescriptor,  
        CNContactFamilyNameKey as CNKeyDescriptor,  
        CNContactEmailAddressesKey as CNKeyDescriptor,  
        CNContactPhoneNumbersKey as CNKeyDescriptor,  
        CNContactPostalAddressesKey as CNKeyDescriptor,  
        CNContactOrganizationNameKey as CNKeyDescriptor,  
        CNContactJobTitleKey as CNKeyDescriptor,  
        CNContactImageDataKey as CNKeyDescriptor  
    \]  
      
    // 3\. Fetch the 'Me' contact  
    return try store.unifiedMeContactWithKeys(toFetch: keys)  
}

**Note:** Remember to include NSContactsUsageDescription in your Info.plist for macOS.

### **8\. QueryGitHubRepo Tool**

**Purpose:** Analyze GitHub repositories for code evidence  
**Parameters:**  
{  
  "type": "object",  
  "required": \["repoUrl"\],  
  "properties": {  
    "repoUrl": {  
      "type": "string",  
      "description": "GitHub repository URL"  
    }  
  }  
}

**Response:**  
{  
  "repository": {  
    "name": "awesome-project",  
    "owner": "johndoe",  
    "description": "A revolutionary new framework",  
    "language": "Swift"  
  }  
}

**Implementation Note:** This tool MUST return the "not configured" error as per the policy above.

### **9\. DeployAgent Tool**

**Purpose:** Spawn sub-agents for specialized processing  
**Parameters:**  
{  
  "type": "object",  
  "required": \["agentType", "input"\],  
  "properties": {  
    "agentType": {  
      "type": "string",  
      "enum": \[  
        "artifact\_ingestion",  
        "code\_analysis",   
        "knowledge\_card\_generation",  
        "writing\_sample\_analysis"  
      \],  
      "description": "Which agent to deploy"  
    },  
    "input": {  
      "type": "object",  
      "description": "Input data for the agent"  
    }  
  }  
}

**Response:**  
{  
  "agentId": "agent\_abc123",  
  "status": "completed" | "failed",  
  "result": {}, // Agent-specific output  
}

### **10\. SetObjectiveStatus Tool**

**Purpose:** Update interview progress and trigger phase transitions  
**Parameters:**  
{  
  "type": "object",  
  "required": \["objectiveId", "status"\],  
  "properties": {  
    "objectiveId": {  
      "type": "string",  
      "description": "ID of the objective to update"  
    },  
    "status": {  
      "type": "string",  
      "enum": \["pending", "in\_progress", "completed", "skipped", "failed"\],  
      "description": "New status"  
    }  
  }  
}

**Response:**  
{  
  "objective": {  
    "id": "collect\_applicant\_profile",  
    "newStatus": "completed"  
  },  
  "phaseStatus": {  
    "currentPhase": "phase\_1\_core\_facts",  
    "progress": 0.67  
  }  
}

### **11\. PersistData Tool**

**Purpose:** Save intermediate data during interview  
**Parameters:**  
{  
  "type": "object",  
  "required": \["dataType", "data"\],  
  "properties": {  
    "dataType": {  
      "type": "string",  
      "enum": \[  
        "applicant\_profile",  
        "skeleton\_timeline",  
        "knowledge\_card",  
        "artifact\_record",  
        "writing\_sample"  
      \]  
    },  
    "data": {  
      "type": "object",  
      "description": "Data to persist"  
    }  
  }  
}

**Response:**  
{  
  "persisted": {  
    "id": "record\_xyz123",  
    "type": "knowledge\_card",  
    "status": "created"  
  }  
}

## **Tool Error Handling**

### **Error Types**

enum ToolError: Error {  
    case invalidParameters(String)  
    case executionFailed(String)  
    case timeout(TimeInterval)  
    case userCancelled  
    case permissionDenied(String)  
}

## **Tool Registration & Discovery**

### **Dynamic Tool Registry**

class ToolRegistry {  
    private var tools: \[String: any InterviewTool\] \= \[:\]  
      
    func register(\_ tool: any InterviewTool) {  
        tools\[tool.name\] \= tool  
    }  
      
    // ... logic to get available tools for LLM ...  
      
    func toolSchemas() \-\> \[JSON\] {  
        tools.values.map { tool in  
            JSON(\[  
                "type": "function",  
                "function": \[  
                    "name": tool.name,  
                    "description": tool.description,  
                    "parameters": tool.parameters  
                \]  
            \])  
        }  
    }  
}

## **Tool Execution Pipeline**

### **Complete Execution Flow**

class ToolExecutor {  
    private let registry: ToolRegistry  
    private var continuations: \[UUID: ContinuationToken\] \= \[:\]  
      
    func handleToolCall(\_ call: ToolCall) async throws \-\> ToolResult {  
        // 1\. Find tool  
        guard let tool \= registry.tools\[call.name\] else {  
            throw ToolError.invalidParameters("Unknown tool: \\(call.name)")  
        }  
          
        // 2\. Execute tool  
        do {  
            let result \= try await tool.execute(call.parameters)  
              
            // 3\. Handle continuation if waiting  
            if case .waiting(\_, let continuation) \= result {  
                continuations\[continuation.id\] \= continuation  
            }  
            return result  
              
        } catch {  
            debugLog("Tool execution failed: \\(tool.name), Error: \\(error)")  
            throw error  
        }  
    }  
      
    func resumeContinuation(\_ id: UUID, with input: JSON) async throws \-\> ToolResult {  
        guard let continuation \= continuations\[id\] else {  
            throw ToolError.invalidParameters("Unknown continuation: \\(id)")  
        }  
          
        continuations.removeValue(forKey: id)  
        return try await continuation.resumeHandler(input)  
    }  
}  
