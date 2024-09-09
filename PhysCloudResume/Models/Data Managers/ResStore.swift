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
  var selectedRes: Resume?

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

    // Now you can use `url` to read the file, load its contents, etc.

    let resume = Resume(
      jobApp: jobApp,
      enabledSources: sources)!
    if let jsonSource = sources.filter { $0.type == .jsonSource }.first {
      resume.initialize(jsonText: jsonSource.content)

      self.addResume(res: resume, to: jobApp)
      return resume
    } else {
     return nil

    }

  }

  func createDuplicate(res: Resume) -> Resume {

    let newResume = Resume(
      jobApp: res.jobApp!, enabledSources: res.enabledSources)
    newResume!.rootNode = res.rootNode!.deepCopy(newResume: newResume!)
    selectedRes = newResume
    res.jobApp!.selectedRes = newResume
    self.addResume(res: newResume!, to: res.jobApp!)
    return newResume!

  }

  func deleteResRef(_ res: Resume) {
    if let index = resumes.firstIndex(of: res) {
      resumes.remove(at: index)
      modelContext!.delete(res)
      saveContext()
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
