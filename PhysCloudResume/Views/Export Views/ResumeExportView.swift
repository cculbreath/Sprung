import SwiftUI

struct ResumeExportView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @State private var selectedResume: Resume?
  @State private var selectedCoverLetter: CoverLetter?
  @State private var selectedStatus: Statuses = .new  // Initial state

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {

      // Resume Section Header
      Text("Resume")
        .font(.headline)
        .padding(.top)

      // Resume Picker
      if let resumes = jobAppStore.selectedApp?.resumes {
        @Bindable var jobApp = jobAppStore.selectedApp!
        Picker("Select a Resume", selection: $selectedResume) {
          Text("None").tag(nil as Resume?)
          ForEach(jobApp.resumes, id: \.self) { resume in
            Text("Created at \(resume.createdDateString)")
              .tag(resume as Resume?)
              .help("Select a resume to customize")
          }
        }
        .pickerStyle(MenuPickerStyle())

        // Export Buttons for Resume
        HStack(spacing: 15) {
          Button("Export PDF") {
            exportResumePDF()
          }
          Button("Export Text") {
            exportResumeText()
          }
          Button("Export JSON") {
            exportResumeJSON()
          }
        }
      }

      // Divider after Resume Section
      Divider()

      // Cover Letter Section Header
      Text("Cover Letter")
        .font(.headline)

      // Cover Letter Picker
      if let coverLetters = jobAppStore.selectedApp?.coverLetters {
        Picker("Select a Cover Letter", selection: $selectedCoverLetter) {
          Text("None").tag(nil as CoverLetter?)
          ForEach(coverLetters, id: \.id) { coverLetter in
            Text("Generated at \(coverLetter.modDate)").tag(coverLetter as CoverLetter?)
          }
        }
        .pickerStyle(MenuPickerStyle())

        // Export Button for Cover Letter
        Button("Export Cover Letter Text") {
          exportCoverLetterText()
        }
      }

      // Divider after Cover Letter Section
      Divider()

      // Application Status Section Header
      Text("Application Status")
        .font(.headline)

      // Segmented Picker for jobApp status
      if let jobApp = jobAppStore.selectedApp {
        Picker("", selection: $selectedStatus) {
          ForEach(Statuses.allCases, id: \.self) { status in
            Text(status.rawValue)
              .tag(status)
          }
        }
        .pickerStyle(SegmentedPickerStyle())
        .onChange(of: selectedStatus) { oldValue, newStatus in
          jobApp.status = newStatus
          jobAppStore
            .updateJobAppStatus(jobApp, to: newStatus) // Assuming you have an update method
        }
      }
    }
    .padding()
    .frame(maxHeight: .infinity, alignment: .top)  // Align content to the top of the view
    .onAppear {
      if let jobApp = jobAppStore.selectedApp {
        selectedStatus = jobApp.status  // Set initial status when the view appears
      }
    }
  }

  // Export Resume PDF
  private func exportResumePDF() {
    guard let resume = selectedResume, let pdfData = resume.pdfData else {
      print("No PDF data available for this resume")
      return
    }

    let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    let fileURL = downloadsURL.appendingPathComponent("\(resume.jobApp?.job_position ?? "unknown").pdf")

    do {
      try pdfData.write(to: fileURL)
      print("PDF exported to \(fileURL)")
    } catch {
      print("Failed to export PDF: \(error)")
    }
  }

  // Export Resume Text
  private func exportResumeText() {
    guard let resume = selectedResume else {
      print("No resume selected")
      return
    }

    let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    let fileURL = downloadsURL.appendingPathComponent("\(resume.jobApp?.job_position ?? "unknown").txt")

    do {
      try resume.textRes.write(to: fileURL, atomically: true, encoding: .utf8)
      print("Text file exported to \(fileURL)")
    } catch {
      print("Failed to export resume text: \(error)")
    }
  }

  // Export Resume JSON
  private func exportResumeJSON() {
    guard let resume = selectedResume else {
      print("No resume selected")
      return
    }

    let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    let fileURL = downloadsURL.appendingPathComponent("\(resume.jobApp?.job_position ?? "unknown").json")

    let jsonString = resume.jsonTxt

    do {
      try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
      print("JSON file exported to \(fileURL)")
    } catch {
      print("Failed to export resume JSON: \(error)")
    }
  }

  // Export Cover Letter Text
  private func exportCoverLetterText() {
    guard let coverLetter = selectedCoverLetter else {
      print("No cover letter selected")
      return
    }

    let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    let fileURL = downloadsURL.appendingPathComponent("\(coverLetter.jobApp?.job_position ?? "")_CoverLetter.txt")

    do {
      try coverLetter.content.write(to: fileURL, atomically: true, encoding: .utf8)
      print("Cover letter text file exported to \(fileURL)")
    } catch {
      print("Failed to export cover letter text: \(error)")
    }
  }
}
