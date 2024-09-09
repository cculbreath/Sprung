import SwiftData

@Observable final class JobAppStore {
  var jobApps: [JobApp] = []
  var selectedApp: JobApp?
  var form = JobAppForm()

  private var modelContext: ModelContext?
  init() {

  }
  func initialize(context: ModelContext) {
    modelContext = context
    loadJobApps()  // Load data from the database when the store is initialized
  }

  // Load JobApps from the database

  private func loadJobApps() {
    let descriptor = FetchDescriptor<JobApp>()
    do {
      jobApps = try modelContext!.fetch(descriptor)
    } catch {
      print("Failed to fetch JobApps: \(error)")
    }
  }
  // Methods to manage jobApps

  func addJobApp(_ jobApp: JobApp) -> JobApp? {
    jobApps.append(jobApp)
    modelContext!.insert(jobApp)
    saveContext()
    return jobApps.last
  }
  func deleteSelected() {
    guard let deleteMe = selectedApp else {
      fatalError("No job application available to delete.")
    }

    self.deleteJobApp(deleteMe)
    selectedApp = self.jobApps.last  //!FixMe Problematic?
  }
  func deleteJobApp(_ jobApp: JobApp) {
    if let index = jobApps.firstIndex(of: jobApp) {
      jobApps.remove(at: index)
      modelContext!.delete(jobApp)
      saveContext()
    }
  }
  private func populateFormFromObj(_ jobApp: JobApp) {
    form.populateFormFromObj(jobApp)
  }

  func editWithForm(_ jobApp: JobApp? = nil) {
    let jobAppEditing = jobApp ?? selectedApp
    guard let jobAppEditing = jobAppEditing else {
      fatalError("No job application available to edit.")
    }
    self.populateFormFromObj(jobAppEditing)
  }
  func cancelFormEdit(_ jobApp: JobApp? = nil) {
    let jobAppEditing = jobApp ?? selectedApp
    guard let jobAppEditing = jobAppEditing else {
      fatalError("No job application available to restore state.")
    }
    self.populateFormFromObj(jobAppEditing)
  }

  func saveForm(_ jobApp: JobApp? = nil) {
    let jobAppToSave = jobApp ?? selectedApp
    guard let jobAppToSave = jobAppToSave else {
      fatalError("No job application available to save.")
    }
    jobAppToSave.assignPropsFromForm(form)
    saveContext()

  }

  // Save changes to the database
  private func saveContext() {
    do {
      try modelContext!.save()
      print("saved")
    } catch {
      print("Failed to save context: \(error)")
    }
  }
}
