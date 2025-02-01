import SwiftData

@Observable final class JobAppStore {
    var jobApps: [JobApp] = []
    var selectedApp: JobApp?
    var form = JobAppForm()
    var resStore: ResStore?
    var coverLetterStore: CoverLetterStore?

    private var modelContext: ModelContext?
    init() {}

    func initialize(context: ModelContext, resStore: ResStore, coverLetterStore: CoverLetterStore) {
        modelContext = context
        self.resStore = resStore
        loadJobApps() // Load data from the database when the store is initialized
        self.coverLetterStore = coverLetterStore
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
    func updateJobAppStatus(_ jobApp: JobApp, to newStatus: Statuses) {
        jobApp.status = newStatus
//    saveContext()
        // Handle additional logic like saving or notifying listeners
    }

    func addJobApp(_ jobApp: JobApp) -> JobApp? {
        coverLetterStore!
            .createBlank(jobApp: jobApp)
        jobApps.append(jobApp)
        modelContext!.insert(jobApp)
//    saveContext()
        return jobApps.last
    }

    func deleteSelected() {
        guard let deleteMe = selectedApp else {
            fatalError("No job application available to delete.")
        }

        deleteJobApp(deleteMe)
        selectedApp = jobApps.last //! FixMe Problematic?
    }

    func deleteJobApp(_ jobApp: JobApp) {
        if let index = jobApps.firstIndex(of: jobApp) {
            if let resStore = resStore {
                for resume in jobApp.resumes {
                    resStore.deleteRes(resume)
                }
                jobApps.remove(at: index)
                modelContext!.delete(jobApp)

//        saveContext()  //Error thrown here}
                if selectedApp == jobApp {
                    selectedApp = nil
                }
                if selectedApp == nil {
                    selectedApp = jobApps.first
                }
            } else {
                print("ResStore ref not here!")
            }
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
        populateFormFromObj(jobAppEditing)
    }

    func cancelFormEdit(_ jobApp: JobApp? = nil) {
        let jobAppEditing = jobApp ?? selectedApp
        guard let jobAppEditing = jobAppEditing else {
            fatalError("No job application available to restore state.")
        }
        populateFormFromObj(jobAppEditing)
    }

    func saveForm(_ jobApp: JobApp? = nil) {
        let jobAppToSave = jobApp ?? selectedApp
        guard let jobAppToSave = jobAppToSave else {
            fatalError("No job application available to save.")
        }
        jobAppToSave.assignPropsFromForm(form)
//    saveContext()
    }

    func updateJobApp(_ updated: JobApp) {
        // Make sure we’re actually tracking this JobApp in our array
        if let index = jobApps.firstIndex(of: updated) {
            // Update the array in case you need to reflect changes in memory
            jobApps[index] = updated
        } else {
            print("Warning: updateJobApp called for a JobApp not in jobApps.")
        }

        // Save the updated data to SwiftData (if you want to do so automatically)
        do {
            try modelContext?.save()
            print("JobAppStore: Successfully updated and saved changes for \(updated).")
        } catch {
            print("JobAppStore: Failed to save updated JobApp. Error: \(error)")
        }
    }

    // Save changes to the database
    private func saveContext() {
        print("don't call this manually!")
        do {
            try modelContext!.save()
            print("saved")
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
