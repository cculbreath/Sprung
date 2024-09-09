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
          for (label) in labelsArray {
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
          for (skill) in skillsArray {
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

          for (job) in jobDict {
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
          for schoolDict in educationArray {
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
          for language in languagesArray {
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

          for projectDict in projectsArray {
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
              for example in examples {
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
          for publication in publicationsArray {
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
                        name: "Authors",
                        value: "",
                        status: LeafStatus.isNotLeaf, resume: res))
                    for author in authorArray {
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
    var json: [String: Any] = [:]

    if let myRootNode = self.rootNode {
      // Add back the meta field
      json["meta"] = ["format": "FRESH@0.6.0", "version": "0.1.0"]

      // Recursive function to traverse the tree
      func traverseTreeNode(_ node: TreeNode) -> Any? {
        var result: [String: Any] = [:]

        // Sort children by myIndex
        let sortedChildren = node.children?.sorted { $0.myIndex < $1.myIndex } ?? []

        for child in sortedChildren {
          if !child.name.isEmpty {
            if child.status == .isNotLeaf {
              result[child.name] = traverseTreeNode(child)
            } else {
              result[child.name] = child.value
            }
          }
        }
        return result.isEmpty ? node.value : result
      }

      // Process rootNode's children
      let sortedRootChildren = myRootNode.children?.sorted { $0.myIndex < $1.myIndex } ?? []
      for child in sortedRootChildren {
        switch child.name {
          case "Section Labels":
            json["section-labels"] = traverseTreeNode(child)
          case "Contact Info":
            json["contact"] = traverseTreeNode(child)
          case "Summary":
            if let summaryArray = child.children?.compactMap({ $0.value }), !summaryArray.isEmpty {
              json["summary"] = summaryArray
            }
          case "Labels":
            if let labelsArray = child.children?.compactMap({ $0.value }), !labelsArray.isEmpty {
              json["labels"] = labelsArray
            }
          case "Skills and Expertise":
            if let skillsArray = child.children?.compactMap({ $0.value }), !skillsArray.isEmpty {
              json["skills-and-expertise"] = skillsArray
            }
          case "Employment":
            var employmentArray: [[String: Any]] = []
            for jobNode in child.children ?? [] {
              var jobDict: [String: Any] = [:]
              if !jobNode.name.isEmpty { jobDict["employer"] = jobNode.name }
              for jobDetail in jobNode.children ?? [] {
                if jobDetail.name == "highlights",
                   let highlightsArray = jobDetail.children?.compactMap({ $0.value }),
                   !highlightsArray.isEmpty {
                  jobDict[jobDetail.name] = highlightsArray
                } else if !jobDetail.name.isEmpty {
                  jobDict[jobDetail.name] = jobDetail.value
                }
              }
              if !jobDict.isEmpty {
                employmentArray.append(jobDict)
              }
            }
            json["employment"] = employmentArray
          case "Education":
            var educationArray: [[String: Any]] = []
            for schoolNode in child.children ?? [] {
              var schoolDict: [String: Any] = [:]
              if !schoolNode.name.isEmpty { schoolDict["institution"] = schoolNode.name }
              for schoolDetail in schoolNode.children ?? [] {
                if !schoolDetail.name.isEmpty {
                  schoolDict[schoolDetail.name] = schoolDetail.value
                }
              }
              if !schoolDict.isEmpty {
                educationArray.append(schoolDict)
              }
            }
            json["education"] = educationArray
          case "Languages and Frameworks":
            if let languagesArray = child.children?.compactMap({ $0.value }), !languagesArray.isEmpty {
              json["languages"] = languagesArray
            }
          case "Projects and Hobbies":
            var projectsArray: [[String: Any]] = []
            for projectNode in child.children ?? [] {
              var projectDict: [String: Any] = [:]
              if !projectNode.name.isEmpty { projectDict["title"] = projectNode.name }

              var examplesArray: [[String: String]] = []
              for example in projectNode.children ?? [] {
                var exampleDict: [String: String] = [:]
                for detail in example.children ?? [] {
                  if detail.name.lowercased() == "name", !detail.value.isEmpty {
                    exampleDict["name"] = detail.value
                  } else if detail.name.lowercased() == "description", !detail.value.isEmpty {
                    exampleDict["description"] = detail.value
                  }
                }
                if !exampleDict.isEmpty {
                  examplesArray.append(exampleDict)
                }
              }

              if !examplesArray.isEmpty {
                projectDict["examples"] = examplesArray
                projectsArray.append(projectDict)
              }
            }
            json["projects-and-hobbies"] = projectsArray
          case "Publications":
            var publicationsArray: [[String: Any]] = []
            for publicationNode in child.children ?? [] {
              var publicationDict: [String: Any] = [:]
              if !publicationNode.name.isEmpty { publicationDict["title"] = publicationNode.name }
              for publicationDetail in publicationNode.children ?? [] {
                if publicationDetail.name == "Authors",
                   let authorsArray = publicationDetail.children?.compactMap({ $0.value }),
                   !authorsArray.isEmpty {
                  publicationDict["authors"] = authorsArray
                } else if !publicationDetail.name.isEmpty {
                  publicationDict[publicationDetail.name] = publicationDetail.value
                }
              }
              if !publicationDict.isEmpty {
                publicationsArray.append(publicationDict)
              }
            }
            json["publications"] = publicationsArray
          case "More Information":
            if let moreInfoValue = child.children?.first?.value, !moreInfoValue.isEmpty {
              json["more-info"] = moreInfoValue
            }
          default:
            break
        }
      }
    }

    // Serialize the rebuilt JSON
    do {
      let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted])
      return String(data: jsonData, encoding: .utf8) ?? ""
    } catch {
      print("Error serializing JSON: \(error)")
      return ""
    }
  }
}
