import Foundation
import SwiftyJSON

/// Test script to demonstrate dynamic JSON manipulation with job categorization
class TestDynamicJSON {
    
    /// Add job categories to employment section without modifying any Swift structs
    static func demonstrateJobCategorization() {
        print("🧪 Testing Dynamic JSON Job Categorization")
        print("==========================================\n")
        
        // Sample JSON with employment data
        let sampleJSON = """
        {
            "employment": {
                "Apple Inc": {
                    "position": "Senior Software Engineer",
                    "start": "2020",
                    "end": "2023",
                    "location": "Cupertino, CA",
                    "highlights": ["Led iOS team", "Architected SwiftUI components"]
                },
                "Stanford University": {
                    "position": "Lecturer - Computer Science",
                    "start": "2018",
                    "end": "2020",
                    "location": "Stanford, CA",
                    "highlights": ["Taught iOS Development", "Mentored 200+ students"]
                },
                "Tech Consulting LLC": {
                    "position": "Mobile Development Consultant",
                    "start": "2017",
                    "end": "2018",
                    "location": "Remote",
                    "highlights": ["Delivered 5 iOS apps", "Advised on architecture"]
                }
            },
            "keys-in-editor": ["employment", "skills-and-expertise"]
        }
        """
        
        guard let data = sampleJSON.data(using: .utf8) else {
            print("❌ Failed to convert sample JSON to data")
            return
        }
        
        do {
            var json = try JSON(data: data)
            print("📄 Original structure:")
            printEmploymentStructure(json["employment"])
            
            // Transform flat employment into categorized structure
            let categorizedEmployment = categorizeEmployment(json["employment"])
            
            // Replace employment with categorized version
            json["employment"] = categorizedEmployment
            
            print("\n📊 Categorized structure:")
            printEmploymentStructure(json["employment"])
            
            // Show the JSON output
            if let jsonString = json.rawString(.utf8, options: .prettyPrinted) {
                print("\n📤 Final JSON:")
                print(jsonString)
            }
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    /// Categorize employment entries based on job type
    private static func categorizeEmployment(_ employment: JSON) -> JSON {
        var categorized = JSON()
        
        for (company, details) in employment {
            let position = details["position"].stringValue.lowercased()
            
            // Determine category
            let category: String
            if position.contains("teach") || position.contains("lecturer") || position.contains("professor") {
                category = "Teaching"
            } else if position.contains("consult") {
                category = "Consulting"
            } else {
                category = "Engineering"
            }
            
            // Initialize category if needed
            if categorized[category].null != nil {
                categorized[category] = JSON()
            }
            
            // Add to category
            categorized[category][company] = details
        }
        
        return categorized
    }
    
    /// Print employment structure for visualization
    private static func printEmploymentStructure(_ employment: JSON) {
        for (key, value) in employment {
            if value.type == .dictionary && value["position"].exists() {
                // Direct employment entry
                print("  - \(key): \(value["position"].stringValue)")
            } else {
                // Category
                print("  📁 \(key):")
                for (company, details) in value {
                    print("    - \(company): \(details["position"].stringValue)")
                }
            }
        }
    }
    
    /// Demonstrate adding custom fields dynamically
    static func demonstrateCustomFields() {
        print("\n\n🧪 Testing Dynamic Custom Fields")
        print("================================\n")
        
        let simpleJSON = """
        {
            "skills-and-expertise": [
                {"title": "Swift", "description": "5 years expert level"},
                {"title": "Python", "description": "3 years proficient"}
            ]
        }
        """
        
        guard let data = simpleJSON.data(using: .utf8) else { return }
        
        do {
            var json = try JSON(data: data)
            
            // Add proficiency level dynamically to each skill
            if var skills = json["skills-and-expertise"].array {
                for (index, skill) in skills.enumerated() {
                    var updatedSkill = skill
                    
                    // Extract years from description
                    let description = skill["description"].stringValue
                    if let range = description.range(of: #"(\d+) years?"#, options: .regularExpression) {
                        let years = String(description[range]).components(separatedBy: " ")[0]
                        updatedSkill["yearsExperience"] = JSON(years)
                        updatedSkill["proficiencyLevel"] = JSON(determineProficiency(Int(years) ?? 0))
                    }
                    
                    skills[index] = updatedSkill
                }
                json["skills-and-expertise"] = JSON(skills)
            }
            
            print("📄 Enhanced skills with dynamic fields:")
            if let jsonString = json.rawString(.utf8, options: .prettyPrinted) {
                print(jsonString)
            }
            
        } catch {
            print("❌ Error: \(error)")
        }
    }
    
    private static func determineProficiency(_ years: Int) -> String {
        switch years {
        case 0...1: return "Beginner"
        case 2...3: return "Intermediate"
        case 4...5: return "Advanced"
        default: return "Expert"
        }
    }
}

// Example usage (would be called from a test or playground):
// TestDynamicJSON.demonstrateJobCategorization()
// TestDynamicJSON.demonstrateCustomFields()