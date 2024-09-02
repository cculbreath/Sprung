import Foundation
import SwiftData

extension Resume {
   static func buildTree(from jsonData: Data) -> TreeNode {
       let rootNode = TreeNode(
        name: "root",
        value: "",
        status: LeafStatus.isNotLeaf)
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
                            status: LeafStatus.isNotLeaf))
                    for (key, myValue) in sectionLabelsDict {
                        sectionLabels.addChild(
                            TreeNode(
                                name: key,
                                value: myValue, status: LeafStatus.saved))
                    }
                }
                if let contactDict = json["contact"] as? [String: Any] {
                    let contact = rootNode.addChild(
                        TreeNode(
                            name: "Contact Info",
                            value: "",
                            status: LeafStatus.isNotLeaf))

                    for (key, myValue) in contactDict {
                        switch myValue {
                            case let strValue as String:
                                contact.addChild(
                                    TreeNode(
                                        name: key,
                                        value: strValue,
                                        status: LeafStatus.disabled))
                            case let locDict as [String: String]:
                                let locNode =
                                contact
                                    .addChild(
                                        (TreeNode(
                                            name: key,
                                            value: "",
                                            status: LeafStatus.isNotLeaf
                                        ))
                                    )
                                for (myKey, theValue) in locDict {
                                    locNode.addChild(
                                        TreeNode(
                                            name: myKey,
                                            value: theValue,
                                            status: LeafStatus.disabled
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
                            status: LeafStatus.isNotLeaf))
                    summary.addChild(
                        TreeNode(
                            name: "", value: summaryArray[0],
                            status: LeafStatus.saved))

                }

                // Initialize labels
                if let labelsArray = json["labels"] as? [String] {
                    let labels = rootNode.addChild(
                        TreeNode(
                            name: "Labels", value: "",
                            status: LeafStatus.isNotLeaf))
                    for (label) in labelsArray {
                        labels.addChild(
                            TreeNode(
                                name: "", value: label, status: LeafStatus.saved
                            ))
                    }
                }
                // Initialize skills and expertise
                if let skillsArray = json["skills-and-expertise"] as? [String] {
                    let skills = rootNode.addChild(
                        TreeNode(
                            name: "Skills and Expertise", value: "",
                            status: LeafStatus.isNotLeaf))
                    for (skill) in skillsArray {
                        skills.addChild(
                            TreeNode(
                                name: "", value: skill, status: LeafStatus.saved
                            ))
                    }
                }

                // Initialize employment history
                if let jobDict = json["employment"] as? [[String: Any]] {
                    let employment = rootNode.addChild(
                        TreeNode(
                            name: "Employment", value: "",
                            status: LeafStatus.isNotLeaf))

                    for (job) in jobDict {
                        let jobNode =
                        employment
                            .addChild(
                                TreeNode(
                                    name: job["employer"] as! String,
                                    value: "",
                                    status: LeafStatus.isNotLeaf
                                )
                            )
                        for (key, val) in job {
                            switch val {
                                case let strValue as String:
                                    jobNode.addChild(
                                        TreeNode(
                                            name: key,
                                            value: strValue,
                                            status: LeafStatus.disabled))
                                case let highlightsArray as [String]:
                                    let highlightParent =
                                    jobNode
                                        .addChild(
                                            (TreeNode(
                                                name: key,
                                                value: "",
                                                status: LeafStatus.isNotLeaf
                                            ))
                                        )
                                    for myHighlight in highlightsArray {
                                        highlightParent.addChild(
                                            TreeNode(
                                                name: "",
                                                value: myHighlight,
                                                status: LeafStatus.saved
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
                            status: LeafStatus.isNotLeaf
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
                                    status: LeafStatus.isNotLeaf
                                )
                            )
                            for (key, value) in schoolDict {
                                if let stringValue = value as? String {
                                    schoolNode.addChild(
                                        TreeNode(
                                            name: key,
                                            value: stringValue,
                                            status: LeafStatus.disabled
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
                            status: LeafStatus.isNotLeaf

                        ))
                    for language in languagesArray {
                        languageNode.addChild(
                            TreeNode(
                                name: "",
                                value: language,
                                status: LeafStatus.saved
                            ))
                    }
                }
                if let projectsArray = json["projects-and-hobbies"]
                    as? [[String: Any]]
                {
                    let projectNode = rootNode.addChild(
                        TreeNode(
                            name: "Projects and Hobbies",
                            value: "",
                            status: LeafStatus.isNotLeaf))
                    for hobby in projectsArray {
                        let hobbNode = projectNode.addChild(
                            TreeNode(
                                name: hobby["title"] as! String,
                                value: "",
                                status: LeafStatus.isNotLeaf)
                        )
                        if let examples = hobby["examples"]
                            as? [[String: String]]
                        {
                            for example in examples {
                                hobbNode
                                    .addChild(
                                        TreeNode(
                                            name: "Name",
                                            value: example["name"] ?? "",
                                            status: LeafStatus.saved))
                                hobbNode.addChild(
                                    TreeNode(
                                        name: "Description",
                                        value: example["description"] ?? "",
                                        status: LeafStatus.saved))
                            }
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
                            status: LeafStatus.isNotLeaf
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
                                            LeafStatus.isNotLeaf
                                    ))
                                for (key, val) in publication {
                                    switch val {
                                        case let strVal as String:
                                            paperNode.addChild(
                                                TreeNode(
                                                    name: key,
                                                    value: strVal,
                                                    status: LeafStatus.disabled
                                                ))

                                        case let authorArray as [String]:
                                            let authorNode = paperNode.addChild(
                                                TreeNode(
                                                    name: "Authors",
                                                    value: "",
                                                    status: LeafStatus.isNotLeaf))
                                            for author in authorArray {
                                                authorNode
                                                    .addChild(
                                                        TreeNode(
                                                            name: "",
                                                            value: author,
                                                            status: LeafStatus
                                                                .disabled)
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
                    let infoNode = rootNode
                        .addChild(
                            TreeNode(
                                name: "More Information",
                                value: "",
                                status: LeafStatus.isNotLeaf
                            )
                        )
                    infoNode.addChild(
                        TreeNode(
                            name: "", value: moreInfoString,
                            status: LeafStatus.saved))
                }
            } else {
                print("could not read json")
            }
        } catch {
            print("an error was thrown \(error)")
        }
       return rootNode
    }
}
