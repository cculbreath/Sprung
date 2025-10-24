# **Onboarding Interview \- Error Recovery & Contingency Planning**

## **Overview**

This document identifies potential failure points in the interview system and provides specific recovery strategies without over-engineering solutions.

## **Critical Failure Points**

### **1\. OpenAI API Failures**

**Potential Issues:**

* Rate limiting  
* Network timeouts  
* Service outages  
* Token limit exceeded  
* Invalid responses

**Recovery Strategies:**  
enum APIRecovery {  
    case rateLimit:  
        // Simple exponential backoff  
        var delay: TimeInterval \= 1.0  
        for attempt in 1...3 {  
            try? await Task.sleep(for: .seconds(delay))  
            if let response \= try? await callAPI() { return response }  
            delay \*= 2  
        }  
        throw APIError.rateLimitExceeded  
          
    case timeout:  
        // Handled by StreamWatchdog for inactivity.  
        // For connection timeouts, a single retry may be warranted.  
        debugLog("API connection timed out, retrying once.")  
        return try await callAPI(timeout: currentTimeout \* 2\)  
          
    case tokenLimit:  
        // Truncate context and retry  
        let truncatedMessages \= messages.suffix(5)  // Keep last 5 messages  
        return try await callAPI(messages: truncatedMessages)  
          
    case malformedResponse:  
        // Escalate model  
        debugLog("Malformed response, escalating to o1 for hard reasoning.")  
        let escalatedCfg \= ModelProvider.escalate(currentCfg)  
        return try await callAPI(config: escalatedCfg)  
}

### **2\. User Abandonment**

**Scenarios:**

* User closes app mid-interview  
* User doesn't respond to prompts  
* User leaves for extended period

Recovery:  
We use a lightweight, reliable checkpointing actor that saves an ordered ring buffer of the last N checkpoints to a single file atomically. This replaces the brittle UserDefaults dictionary approach.  
// Note: Session struct and Phase enum must be Codable  
struct Checkpoint: Codable {  
    let t: Date  
    let phase: Phase  
    let objectivesDone: \[String\]  
}

actor Checkpoints {  
    private var last: \[Checkpoint\] \= \[\]       // keep last N only  
    private let url: URL \= {  
        let appSup \= FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)\[0\]  
        try? FileManager.default.createDirectory(at: appSup, withIntermediateDirectories: true)  
        return appSup.appendingPathComponent("Interview.checkpoints.json")  
    }()  
    private let maxN \= 8

    func save(from s: Session) async {  
        last.append(.init(t: Date(), phase: s.phase, objectivesDone: Array(s.objectivesDone)))  
        if last.count \> maxN { last.removeFirst(last.count \- maxN) }  
        do {  
            let data \= try JSONEncoder().encode(last)  
            try data.write(to: url, options: .atomic)     // atomic write  
        } catch {   
            debugLog("Checkpoint save failed: \\(error)")  
        }  
    }

    func restoreLatest() async \-\> Session? {  
        guard let data \= try? Data(contentsOf: url),  
              let arr \= try? JSONDecoder().decode(\[Checkpoint\].self, from: data),  
              let cp \= arr.max(by: { $0.t \< $1.t }) else { return nil }  
          
        // Restore session data  
        var s \= Session()  
        s.phase \= cp.phase  
        s.objectivesDone \= Set(cp.objectivesDone)  
        return s  
    }  
}

// On app launch, check for incomplete session  
func checkForIncompleteSession() async \-\> Session? {  
    let checkpointActor \= Checkpoints()  
    guard let session \= await checkpointActor.restoreLatest() else {  
        return nil  
    }  
      
    // If session is not complete, offer to resume  
    if session.phase \!= .complete {  
        return session  
    }  
      
    return nil  
}

// Simple resume prompt  
func offerResume(\_ session: Session) {  
    // "You have an incomplete interview. Resume?"  
    // \[Resume\] \[Start Over\]  
}

### **3\. Tool Execution Failures**

**Common Issues:**

* File upload fails  
* URL fetch fails  
* Contact access denied  
* GitHub API rate limit

**Tool-Specific Recovery:**  
extension ToolExecutor {  
    func handleToolFailure(\_ tool: String, error: Error) async \-\> ToolResult {  
        switch (tool, error) {  
        case ("get\_user\_upload", FileError.tooLarge):  
            return .error(.executionFailed("File too large. Please upload a file under 10MB."))  
              
        case ("get\_user\_upload", FileError.invalidFormat):  
            return .error(.executionFailed("Unsupported format. Please upload PDF, DOCX, or TXT."))  
              
        case ("fetch\_url", \_):  
            // Auth-dependent features are out of scope  
            return .error(.executionFailed("URL fetching is not configured. Please skip for now."))  
              
        case ("get\_macos\_contact", ContactError.denied):  
            return .error(.executionFailed("Contacts access denied. Please enable in System Settings or enter manually."))  
              
        case ("query\_github\_repo", \_):  
            return .error(.executionFailed("GitHub analysis is not configured. Please skip for now."))  
              
        default:  
            return .error(.executionFailed("Operation failed: \\(error.localizedDescription). Please try another method."))  
        }  
    }  
}

### **4\. Data Validation Failures**

**Issues:**

* Required fields missing  
* Invalid data format  
* Conflicting information

**Validation Recovery:**  
// Handled by submit\_for\_validation tool loop  
// The LLM can re-prompt the user for corrections based on  
// the tool's error response.

### **5\. Agent Processing Failures**

**Issues:**

* Knowledge Card generation fails  
* Malformed agent response

**Agent Recovery:**  
extension AgentManager {  
    func handleAgentFailure(\_ agent: AgentType, error: Error) async \-\> AgentResult {  
        switch agent {  
        case .knowledgeCardGenerator:  
            // Fall back to simpler extraction or escalate  
            debugLog("KCard gen failed, escalating to o1")  
            let escalatedCfg \= ModelProvider.escalate(currentCfg)  
            return await generateKnowledgeCard(config: escalatedCfg)  
              
        case .artifactProcessor:  
            // Mark as unprocessed, continue  
            return AgentResult(  
                status: .partial,  
                data: \["text": extractedText, "processed": false\]  
            )  
        }  
    }  
}

### **6\. State Corruption**

**Issues:**

* Invalid state transitions  
* Checkpoint data corrupted

State Recovery:  
The minimal state machine (Session/Phase) dramatically reduces this risk.

* If a checkpoint is corrupt, restoreLatest will fail and nil will be returned, triggering a new session.  
* Invalid transitions are prevented by the InterviewState actor's logic.

## **Timeout Management**

### **30s Inactivity Policy**

We will use a stream-aware inactivity timer that resets on *any* activity (token, tool call, event) from the Responses API. This replaces the global 30s wall-clock timeout.  
actor StreamWatchdog {  
    private var lastActivity \= Date()  
    private var cancelled \= false

    func noteActivity() {   
        lastActivity \= Date()   
    }  
      
    func cancel() {   
        cancelled \= true   
    }

    func start(timeoutSeconds: TimeInterval \= 30, onTimeout: @escaping () \-\> Void) {  
        Task.detached { \[weak self\] in  
            guard let self else { return }  
            while \!self.cancelled {  
                // Check every 0.5 seconds  
                try? await Task.sleep(nanoseconds: 500\_000\_000)   
                  
                // If cancelled while sleeping, exit  
                if self.cancelled { return }  
                  
                if Date().timeIntervalSince(self.lastActivity) \> timeoutSeconds {  
                    if \!self.cancelled { // Double-check before firing  
                        onTimeout()  
                    }  
                    return  
                }  
            }  
        }  
    }  
}

**Usage with the Responses API stream:**  
let watchdog \= StreamWatchdog()  
let task \= Task {  
    // Start the watchdog, which will cancel this task on inactivity  
    watchdog.start {   
        debugLog("Stream inactive for 30s, cancelling task.")  
        task.cancel()   
    }  
      
    var fullResponse \= ""  
    for try await event in client.responses.stream(/\* ... \*/) {  
        // ANY activity resets the timer  
        watchdog.noteActivity()   
          
        switch event {  
        case .text(let text):  
            fullResponse \+= text  
            // ... update UI ...  
        case .toolCall(let toolCall):  
            // ... handle tool call ...  
        case .reasoning(let reasoning):  
            // ... handle reasoning step ...  
        }  
    }  
    return fullResponse  
}

// Don't forget to cancel the watchdog when the task finishes successfully  
let result \= try await task.value  
watchdog.cancel() 

## **Network Resilience**

### **Connection Monitoring**

import Network

class NetworkMonitor {  
    private let monitor \= NWPathMonitor()  
    @Published var isConnected \= true  
      
    func start() {  
        monitor.pathUpdateHandler \= { \[weak self\] path in  
            self?.isConnected \= path.status \== .satisfied  
        }  
        monitor.start(queue: .global())  
    }  
      
    func waitForConnection() async {  
        while \!isConnected {  
            try? await Task.sleep(for: .seconds(1))  
        }  
    }  
}

// Usage in orchestrator  
extension InterviewOrchestrator {  
    func callAPIWithNetworkCheck() async throws \-\> Response {  
        guard networkMonitor.isConnected else {  
            await showOfflineMessage()  
            await networkMonitor.waitForConnection()  
        }  
          
        return try await callAPI()  
    }  
}

## **User Experience During Failures**

### **Failure Messages**

enum UserMessage {  
    case apiDown:  
        return "Service is temporarily unavailable. Your progress is saved. Try again in a few minutes."  
          
    case networkError:  
        return "Connection issue. Please check your internet and try again."  
          
    case saveFailed:  
        return "Couldn't save your progress. Keep this window open and try again."  
          
    case uploadFailed:  
        return "Upload failed. Try a smaller file or different format."  
          
    case validationFailed(fields: \[String\]):  
        return "Please complete: \\(fields.joined(separator: ", "))"  
          
    case resumeAvailable:  
        return "Welcome back\! Would you like to continue where you left off?"  
}

## **Summary**

This contingency plan provides:

1. **Specific recovery strategies** for each failure type  
2. **Simple implementation patterns** without over-engineering  
3. **User-friendly error messages**  
4. **Reliable progress preservation** with the Checkpoints actor  
5. **Stream-aware inactivity timeouts** with StreamWatchdog  
6. **Graceful degradation** for unconfigured features

The key principle: **Fail gracefully, save progress, keep the user informed, and always provide a path forward.**