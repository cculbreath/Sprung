//
//  swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/30/24.
//

import SwiftData

@Observable
final class ResRefStore {
  var resRefs: [ResRef] = []
  private var modelContext: ModelContext?
  var defaultSources: [ResRef] {
    return resRefs.filter { $0.enabledByDefault == true }
  }
  init() {}
  func initialize(context: ModelContext) {
    self.modelContext = context
    loadResRefs()  // Load data from the database when the store is initialized
  }
  private func loadResRefs() {
    let descriptor = FetchDescriptor<ResRef>()
    do {
      resRefs = try modelContext!.fetch(descriptor)
    } catch {
      print("Failed to fetch Resume Refs: \(error)")
    }
  }

  @discardableResult
  func addResRef(_ resRef: ResRef, res: Resume?) -> ResRef {

    resRefs.append(resRef)
    modelContext!.insert(resRef)
    saveContext()
    if let resume = res {
      resume.enabledSources.append(resRef)
    }
    return resRef
  }

  func deleteResRef(_ resRef: ResRef) {
    if let index = resRefs.firstIndex(of: resRef) {
      resRefs.remove(at: index)
      
      modelContext!.delete(resRef)
      saveContext()
    }
  }
  var areRefsOk: Bool {
    return resRefs.contains { $0.type == .resumeSource && $0.enabledByDefault } &&
    resRefs.contains { $0.type == .jsonSource && $0.enabledByDefault }
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
