import Foundation
import SwiftData

extension Resume {
  func buildTree(from jsonData: Data, res: Resume) -> TreeNode {
    let rootNode = TreeNode(
      name: "root",
      value: "",
      status: LeafStatus.isNotLeaf,
      resume: res
    )
    do {
      if let json = try JSONSerialization.jsonObject(
        with: jsonData, options: []) as? [String: Any]
      {
        // Initialize section labels
        if let sectionLabelsDict = json["section-labels"]
          as? [String: String]
        {
          let sectionLabels = rootNode.addChild(
            TreeNode(
              name: "Section Labels",
              value: "",
              status: LeafStatus.isNotLeaf, resume: res))
          for (key, myValue) in sectionLabelsDict {
            sectionLabels.addChild(
              TreeNode(
                name: key,
                value: myValue, status: LeafStatus.saved,
                resume: res))
          }
        }
        if let contactDict = json["contact"] as? [String: Any] {
          let contact = rootNode.addChild(
            TreeNode(
              name: "Contact Info",
              value: "",
              status: LeafStatus.isNotLeaf,
              resume: res))

          for (key, myValue) in contactDict {
            switch myValue {
            case let strValue as String:
              contact.addChild(
                TreeNode(
                  name: key,
                  value: strValue,
                  status: LeafStatus.disabled, resume: res))
            case let locDict as [String: String]:
              let locNode =
                contact
                .addChild(
                  (TreeNode(
                    name: key,
                    value: "",
                    status: LeafStatus.isNotLeaf, resume: res
                  ))
                )
              for (myKey, theValue) in locDict {
                locNode.addChild(
                  TreeNode(
                    name: myKey,
                    value: theValue,
                    status: LeafStatus.disabled, resume: res
                  ))
              }
            default:
              print("unknown type encountered")
            }
          }
        }
        if let summaryArray = json["summary"] as? [String] {
          let summary = rootNode.addChild(
            TreeNode(
              name: "Summary",
              value: "",
              status: LeafStatus.isNotLeaf, resume: res))
          summary.addChild(
            TreeNode(
              name: "", value: summaryArray[0],
              status: LeafStatus.saved, resume: res))

        }

        // Initialize labels
        if let labelsArray = json["labels"] as? [String] {
          let labels = rootNode.addChild(
            TreeNode(
              name: "Labels", value: "",
              status: LeafStatus.isNotLeaf, resume: res))
          for (index, label) in labelsArray.enumerated() {
            labels.addChild(
              TreeNode(
                name: "", value: label, status: LeafStatus.saved, resume: res
              ))
          }
        }
        // Initialize skills and expertise
        if let skillsArray = json["skills-and-expertise"] as? [String] {
          let skills = rootNode.addChild(
            TreeNode(
              name: "Skills and Expertise", value: "",
              status: LeafStatus.isNotLeaf, resume: res))
          for (index, skill) in skillsArray.enumerated() {
            skills.addChild(
              TreeNode(
                name: "", value: skill, status: LeafStatus.saved, resume: res
              ))
          }
        }

        // Initialize employment history
        if let jobDict = json["employment"] as? [[String: Any]] {
          let employment = rootNode.addChild(
            TreeNode(
              name: "Employment", value: "",
              status: LeafStatus.isNotLeaf, resume: res))

          for (index, job) in jobDict.enumerated() {
            let jobNode =
              employment
              .addChild(
                TreeNode(
                  name: job["employer"] as! String,
                  value: "",
                  status: LeafStatus.isNotLeaf, resume: res
                )
              )
            for (key, val) in job {
              switch val {
              case let strValue as String:
                jobNode.addChild(
                  TreeNode(
                    name: key,
                    value: strValue,
                    status: LeafStatus.disabled, resume: res))
              case let highlightsArray as [String]:
                let highlightParent =
                  jobNode
                  .addChild(
                    (TreeNode(
                      name: key,
                      value: "",
                      status: LeafStatus.isNotLeaf, resume: res
                    ))
                  )
                for myHighlight in highlightsArray {
                  highlightParent.addChild(
                    TreeNode(
                      name: "",
                      value: myHighlight,
                      status: LeafStatus.saved, resume: res
                    ))
                }
              default:
                print("unknown type encountered")
              }
            }
          }
        }
        if let educationArray = json["education"] as? [[String: Any]] {
          let education = rootNode.addChild(
            TreeNode(
              name: "Education",
              value: "",
              status: LeafStatus.isNotLeaf, resume: res
            )
          )
          for (index, schoolDict) in educationArray.enumerated() {
            if let institutionName = schoolDict["institution"]
              as? String
            {
              let schoolNode = education.addChild(
                TreeNode(
                  name: institutionName,
                  value: "",
                  status: LeafStatus.isNotLeaf, resume: res
                )
              )
              for (key, value) in schoolDict {
                if let stringValue = value as? String {
                  schoolNode.addChild(
                    TreeNode(
                      name: key,
                      value: stringValue,
                      status: LeafStatus.disabled, resume: res
                    )
                  )
                }
              }
            }
          }
        }
        if let languagesArray = json["languages"] as? [String] {
          let languageNode = rootNode.addChild(
            TreeNode(

              name: "Languages and Frameworks",
              value: "",
              status: LeafStatus.isNotLeaf, resume: res

            ))
          for (index, language) in languagesArray.enumerated() {
            languageNode.addChild(
              TreeNode(
                name: "",
                value: language,
                status: LeafStatus.saved, resume: res
              ))
          }
        }
        if let projectsArray = json["projects-and-hobbies"] as? [[String: Any]] {
          let projectNode = rootNode.addChild(
            TreeNode(
              name: "Projects and Hobbies",
              value: "",
              status: LeafStatus.isNotLeaf, resume: res)
          )

          for (index, projectDict) in projectsArray.enumerated() {
            guard let projectTitle = projectDict["title"] as? String else {
              print("Skipping project with no title.")
              continue
            }
            let projectNode = projectNode.addChild(
              TreeNode(
                name: projectTitle,
                value: "",
                status: LeafStatus.isNotLeaf, resume: res
              )
            )

            if let examples = projectDict["examples"] as? [[String: String]] {
              for (index, example) in examples.enumerated() {
                if let exampleName = example["name"],
                  let exampleDescription = example["description"]
                {
                  let exampleNode = projectNode.addChild(
                    TreeNode(
                      name: exampleName,
                      value: "",
                      status: LeafStatus.isNotLeaf, resume: res)
                  )
                  exampleNode.addChild(
                    TreeNode(
                      name: "Description",
                      value: exampleDescription,
                      status: LeafStatus.saved, resume: res
                    )
                  )
                }
              }
            } else {
              print("No examples found for project \(projectTitle).")
            }
          }
        }
        if let publicationsArray = json["publications"]
          as? [[String: Any]]
        {
          let pubsNode = rootNode.addChild(
            TreeNode(
              name: "Publications",
              value: "",
              status: LeafStatus.isNotLeaf, resume: res
            )
          )
          for (index, publication) in publicationsArray.enumerated() {
            if let journalStr = publication["journal"] as? String {
              if let yearStr = publication["year"] as? String {
                let nameString = "\(journalStr), \(yearStr)"
                let paperNode = pubsNode.addChild(
                  TreeNode(
                    name: nameString,
                    value: "",
                    status:
                      LeafStatus.isNotLeaf, resume: res
                  ))
                for (key, val) in publication {
                  switch val {
                  case let strVal as String:
                    paperNode.addChild(
                      TreeNode(
                        name: key,
                        value: strVal,
                        status: LeafStatus.disabled, resume: res
                      ))

                  case let authorArray as [String]:
                    let authorNode = paperNode.addChild(
                      TreeNode(
                        name: "authors",
                        value: "",
                        status: LeafStatus.isNotLeaf, resume: res))
                    for (index, author) in authorArray.enumerated() {
                      authorNode
                        .addChild(
                          TreeNode(
                            name: "",
                            value: author,
                            status: LeafStatus
                              .disabled, resume: res)
                        )

                    }
                  default:
                    print("unknown publication attribute")
                  }
                }
              } else {
                print("year can't be read as string")
              }

            } else {
              print("journal is not string")
            }
          }

        }

        if let moreInfoString = json["more-info"] as? String {
          let infoNode =
            rootNode
            .addChild(
              TreeNode(
                name: "More Information",
                value: "",
                status: LeafStatus.isNotLeaf, resume: res
              )
            )
          infoNode.addChild(
            TreeNode(
              name: "", value: moreInfoString,
              status: LeafStatus.saved, resume: res))
        }
      } else {
        print("could not read json")
      }
    } catch {
      print("an error was thrown \(error)")
    }
    return rootNode
  }

  func rebuildJSON() -> String {
    var jsonString = "{\n"

    if let myRootNode = self.rootNode {
      // 1. Add "meta" dynamically
      jsonString += """
        "meta": {
            "format": "FRESH@0.6.0",
            "version": "0.1.0"
        },
        """
      // 1b. Missing Labels
      if let labelsNode = myRootNode.children?.first(where: {
        $0.name == "Labels"
      }) {
        let labelsArray = labelsNode.children?.sorted(by: { $0.myIndex < $1.myIndex })
          .compactMap { $0.value as String }
        if let labelsArray = labelsArray, !labelsArray.isEmpty {
          jsonString += """
            "labels": [
            \(labelsArray.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",\n"))
            ],
            """
        }
      }
      // 2. Traverse and add section-labels dynamically
      jsonString += """
        "section-labels": {
        """
      if let sectionLabelsNode = myRootNode.children?.first(where: { $0.name == "Section Labels" })
      {
        jsonString +=
          sectionLabelsNode.children?.sorted(by: { $0.myIndex < $1.myIndex }).compactMap({ child in
            guard let value = child.value as? String else { return nil }
            return "\"\(child.name)\": \"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
          }).joined(separator: ",\n") ?? ""
      }
      jsonString += "\n},"

      // 3. Traverse and add contact information dynamically
      if let contactInfoNode = myRootNode.children?.first(where: { $0.name == "Contact Info" }) {
        jsonString += """
          "contact": {
          """
        jsonString +=
          contactInfoNode.children?.compactMap({ child in
            if child.name == "location" {
              let locationString =
                child.children?.compactMap({ locChild in
                  guard let value = locChild.value as? String else { return nil }
                  return
                    "\"\(locChild.name)\": \"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
                }).joined(separator: ",\n") ?? ""
              return "\"\(child.name)\": {\n\(locationString)\n}"
            } else if let value = child.value as? String {
              return "\"\(child.name)\": \"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return nil
          }).joined(separator: ",\n") ?? ""
        jsonString += "\n},"
      }

      // 4. Traverse and add summary dynamically
      if let summaryNode = myRootNode.children?.first(where: { $0.name == "Summary" }) {
        let summaryArray = summaryNode.children?.sorted(by: { $0.myIndex < $1.myIndex }).compactMap
        { $0.value as? String }
        if let summaryArray = summaryArray, !summaryArray.isEmpty {
          jsonString += """
            "summary": [
            \(summaryArray.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",\n"))
            ],
            """
        }
      }

      // 5. Traverse and add employment dynamically (sorted by myIndex)
      if let employmentNode = myRootNode.children?.first(where: { $0.name == "Employment" }) {
        jsonString += """
          "employment": [
          """
        let employmentArray =
          employmentNode.children?.sorted(by: { $0.myIndex < $1.myIndex }).compactMap {
            jobNode -> String? in
            var jobDict: [String: Any] = [:]
            if !jobNode.name.isEmpty { jobDict["employer"] = jobNode.name }
            for jobDetail in jobNode.children?.sorted(by: { $0.myIndex < $1.myIndex }) ?? [] {
              if jobDetail.name == "highlights" {
                let highlightsArray = jobDetail.children?.sorted(by: { $0.myIndex < $1.myIndex })
                  .compactMap { $0.value as? String }
                if let highlightsArray = highlightsArray, !highlightsArray.isEmpty {
                  jobDict[jobDetail.name] = highlightsArray
                }
              } else if !jobDetail.name.isEmpty, let value = jobDetail.value as? String {
                jobDict[jobDetail.name] = value
              }
            }
            if !jobDict.isEmpty {
              let jobJSON = jobDict.map { key, value -> String in
                if let arrayValue = value as? [String] {
                  return
                    "\"\(key)\": [\n\(arrayValue.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",\n"))\n]"
                } else if let stringValue = value as? String {
                  return
                    "\"\(key)\": \"\(stringValue.replacingOccurrences(of: "\"", with: "\\\""))\""
                }
                return ""
              }.joined(separator: ",\n")
              return "{\n\(jobJSON)\n}"
            }
            return nil
          }.joined(separator: ",\n") ?? ""
        jsonString += employmentArray
        jsonString += "\n],"
      }

      // 6. Traverse and add education dynamically (sorted by myIndex)
      if let educationNode = myRootNode.children?.first(where: { $0.name == "Education" }) {
        jsonString += """
          "education": [
          """
        let educationArray =
          educationNode.children?.sorted(by: { $0.myIndex < $1.myIndex }).compactMap {
            schoolNode -> String? in
            var schoolDict: [String: Any] = [:]
            if !schoolNode.name.isEmpty { schoolDict["institution"] = schoolNode.name }
            for schoolDetail in schoolNode.children?.sorted(by: { $0.myIndex < $1.myIndex }) ?? [] {
              if !schoolDetail.name.isEmpty, let value = schoolDetail.value as? String {
                schoolDict[schoolDetail.name] = value
              }
            }
            if !schoolDict.isEmpty {
              let schoolJSON = schoolDict.map { key, value -> String in
                return "\"\(key)\": \"\(value as! String)\""
              }.joined(separator: ",\n")
              return "{\n\(schoolJSON)\n}"
            }
            return nil
          }.joined(separator: ",\n") ?? ""
        jsonString += educationArray
        jsonString += "\n],"
      }

      // 7. Traverse and add skills-and-expertise dynamically
      if let skillsNode = myRootNode.children?.first(where: { $0.name == "Skills and Expertise" }) {
        let skillsArray = skillsNode.children?.sorted(by: { $0.myIndex < $1.myIndex }).compactMap {
          $0.value as? String
        }
        if let skillsArray = skillsArray, !skillsArray.isEmpty {
          jsonString += """
            "skills-and-expertise": [
            \(skillsArray.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",\n"))
            ],
            """
        }
      }

      // 8. Traverse and add languages dynamically
      if let languagesNode = myRootNode.children?.first(where: {
        $0.name == "Languages and Frameworks"
      }) {
        let languagesArray = languagesNode.children?.sorted(by: { $0.myIndex < $1.myIndex })
          .compactMap { $0.value as? String }
        if let languagesArray = languagesArray, !languagesArray.isEmpty {
          jsonString += """
            "languages": [
            \(languagesArray.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",\n"))
            ],
            """
        }
      }

      // 9. Traverse and add projects-and-hobbies dynamically
      if let projectsNode = myRootNode.children?.first(where: { $0.name == "Projects and Hobbies" }) {
        jsonString += """
    "projects-and-hobbies": [
    """

        let projectsArray = projectsNode.children?.sorted(by: { $0.myIndex < $1.myIndex }).compactMap { projectNode -> String? in
          var projectString = ""

          // Set the project title
          if !projectNode.name.isEmpty {
            projectString += "\"title\": \"\(projectNode.name)\""
          }

          // Handle examples
          var examplesArray: [String] = []
          for example in projectNode.children?.sorted(by: { $0.myIndex < $1.myIndex }) ?? [] {
            var exampleString = "{"
            // Extract both "name" and "description" from the node's children
             let exampleName = example.name
            if !exampleName.isEmpty {
              exampleString += "\"name\": \"\(exampleName.replacingOccurrences(of: "\"", with: "\\\""))\", "
            }
            if let descriptionNode = example.children?.first(where: { $0.name.lowercased() == "description" }), let description = descriptionNode.value as? String {
              exampleString += "\"description\": \"\(description.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            exampleString += "}"
            examplesArray.append(exampleString)
          }

          // Add examples to project
          if !examplesArray.isEmpty {
            projectString += ", \"examples\": [\n" + examplesArray.joined(separator: ",\n") + "\n]"
          }

          // Wrap the project in curly braces
          return "{\n\(projectString)\n}"

        }.joined(separator: ",\n") ?? ""

        jsonString += projectsArray
        jsonString += "\n],"
      }
      // 10. Traverse and add publications dynamically
      if let publicationsNode = myRootNode.children?.first(where: { $0.name == "Publications" }) {
        jsonString += """
          "publications": [
          """
        let publicationsArray =
          publicationsNode.children?.sorted(by: { $0.myIndex < $1.myIndex }).compactMap {
            pubNode -> String? in
            var pubDict: [String: Any] = [:]
            if !pubNode.name.isEmpty { pubDict["title"] = pubNode.name }
            for pubDetail in pubNode.children?.sorted(by: { $0.myIndex < $1.myIndex }) ?? [] {
              if pubDetail.name == "authors" {
                let authorsArray = pubDetail.children?.sorted(by: { $0.myIndex < $1.myIndex })
                  .compactMap { $0.value as String }
                if let authorsArray = authorsArray, !authorsArray.isEmpty {
                  pubDict[pubDetail.name] = authorsArray
                }
              } else if !pubDetail.name.isEmpty, let value = pubDetail.value as? String {
                pubDict[pubDetail.name] = value
              }
            }
            if !pubDict.isEmpty {
              let pubJSON = pubDict.map { key, value -> String in
                if let arrayValue = value as? [String] {
                  return
                    "\"\(key)\": [\n\(arrayValue.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ",\n"))\n]"
                } else if let stringValue = value as? String {
                  return
                    "\"\(key)\": \"\(stringValue.replacingOccurrences(of: "\"", with: "\\\""))\""
                }
                return ""
              }.joined(separator: ",\n")
              return "{\n\(pubJSON)\n}"
            }
            return nil
          }.joined(separator: ",\n") ?? ""
        jsonString += publicationsArray
        jsonString += "\n],"
      }

      // 11. Traverse and add more-info dynamically
      if let moreInfoNode = myRootNode.children?.first(where: { $0.name == "More Information" }) {
        if let moreInfoValue = moreInfoNode.children?.first?.value as? String,
          !moreInfoValue.isEmpty
        {
          jsonString += """
            "more-info": "\(moreInfoValue.replacingOccurrences(of: "\"", with: "\\\""))"
            """
        }
      }

      // 12. Final addition of closing brace
      jsonString += "\n}"
    }

    return jsonString
  }
}
