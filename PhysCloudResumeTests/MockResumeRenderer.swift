import Foundation

/// Mock resume renderer for testing purposes
struct MockResumeRenderer {
    
    /// Renders a resume from a dictionary structure to text
    /// This mimics the behavior of the production endpoint for testing
    static func renderResume(from resumeDict: [String: Any]) -> String {
        var output = ""
        
        // Extract style
        let style = resumeDict["style"] as? String ?? "Professional"
        output += "=== \(style) Resume ===\n\n"
        
        // Extract sections
        if let sections = resumeDict["sections"] as? [[String: Any]] {
            for section in sections {
                if let sectionName = section["name"] as? String {
                    output += "\(sectionName.uppercased())\n"
                    output += String(repeating: "=", count: sectionName.count) + "\n\n"
                    
                    if let fields = section["fields"] as? [[String: Any]] {
                        for field in fields {
                            if let fieldName = field["name"] as? String,
                               let fieldValue = field["value"] as? String {
                                if fieldValue.isEmpty { continue }
                                
                                if fieldName.lowercased() == "name" {
                                    output += "\(fieldValue)\n\n"
                                } else if fieldName.lowercased() == "description" {
                                    output += "\(fieldValue)\n\n"
                                } else {
                                    output += "\(fieldName): \(fieldValue)\n"
                                }
                            }
                        }
                    }
                    
                    output += "\n"
                }
            }
        }
        
        return output
    }
}
