//
//  swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/30/24.
//

import Foundation
import SwiftData

@Observable
final class ResStore {
  var resumes: [Resume] = []

  private var modelContext: ModelContext?
  init() {}
  func initialize(context: ModelContext) {
    self.modelContext = context
    loadResumes()  // Load data from the database when the store is initialized
  }
  private func loadResumes() {
    let descriptor = FetchDescriptor<Resume>()
    do {
      resumes = try modelContext!.fetch(descriptor)
    } catch {
      print("Failed to fetch Resume Refs: \(error)")
    }
  }
  @discardableResult
  func addResume(res: Resume, to jobApp: JobApp) -> Resume {
    resumes.append(res)
    jobApp.addResume(res)
    modelContext!.insert(res)
    saveContext()
    return res
  }

  @discardableResult
  func create(jobApp: JobApp, sources: [ResRef]) -> Resume? {
    if let modelContext = modelContext {
      print("Model context available")
      print("Creating resume for job application: \(jobApp)")

      let resume = Resume(jobApp: jobApp, enabledSources: sources)!
      print("Resume object created")

      if let jsonSource = sources.filter({ $0.type == .jsonSource }).first {
        print("JSON source found: \(jsonSource)")

        // Build the tree and attach it to the resume
        guard let jsonData = jsonSource.content.data(using: .utf8) else {
          print("Error converting JSON content to data")
          return nil
        }

        resume.rootNode = resume.buildTree(from: jsonData, res: resume)
        print("Resume tree built from JSON data")

        // Insert resume into the model context and save
        modelContext.insert(resume)

        do {
          try modelContext.save()
          print("Model context saved after processing JSON data")
        } catch {
          print("Error saving context: \(error)")
          return nil
        }

        print("Resume successfully saved and processed")
        self.addResume(res: resume, to: jobApp)
        print("Resume added to job application")
        return resume
      } else {
        print("No JSON source found")
        return nil
      }
    } else {
      print("Model context not available")
      return nil
    }
  }
  func createDuplicate(res: Resume) -> Resume {

    let newResume = Resume(
      jobApp: res.jobApp!, enabledSources: res.enabledSources)
    newResume!.rootNode = res.rootNode!.deepCopy(newResume: newResume!)
    res.jobApp!.selectedRes = newResume
    self.addResume(res: newResume!, to: res.jobApp!)
    return newResume!

  }

  func deleteRes(_ res: Resume) {
    if let index = resumes.firstIndex(of: res) {
      if let rootNode = res.rootNode {
        TreeNode.deleteTreeNode(node: rootNode, context: modelContext!) // Recursively delete rootNode and its children
      }
      resumes.remove(at: index)
      modelContext!.delete(res)
      saveContext()
    }
    else {
      print("no rootnode")
    }
  }
  //Form functionality incomplete
  //    private func populateFormFromObj(_ resRef: JobApp) {
  //        form.populateFormFromObj(jobApp)
  //    }
  //
  //
  //    func editWithForm(_ jobApp:JobApp? = nil) {
  //        let jobAppEditing = jobApp ?? selectedApp
  //        guard let jobAppEditing = jobAppEditing else {
  //            fatalError("No job application available to edit.")
  //        }
  //        self.populateFormFromObj(jobAppEditing)
  //    }
  //    func cancelFormEdit(_ jobApp:JobApp? = nil) {
  //        let jobAppEditing = jobApp ?? selectedApp
  //        guard let jobAppEditing = jobAppEditing else {
  //            fatalError("No job application available to restore state.")
  //        }
  //        self.populateFormFromObj(jobAppEditing)
  //    }
  //
  //    func saveForm(_ jobApp:JobApp? = nil) {
  //        let jobAppToSave = jobApp ?? selectedApp
  //        guard let jobAppToSave = jobAppToSave else {
  //            fatalError("No job application available to save.")
  //        }
  //        jobAppToSave.assignPropsFromForm(form)
  //        saveContext()
  //
  //    }

  // Save changes to the database
  private func saveContext() {
    do {
      try modelContext!.save()
    } catch {
      print("Failed to save context: \(error)")
    }
  }
}
