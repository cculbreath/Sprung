import SwiftUI

struct NewAppSheetView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(\.dismiss) private var dismiss

  @AppStorage("scrapingDogApiKey") var scrapingDogApiKey: String = "none"

  @State private var isLoading: Bool = false
  @State private var urlText: String = ""
  @Binding var isPresented: Bool

  var body: some View {
    VStack {
      if isLoading {
        VStack {
          ProgressView("Fetching job details...")
            .progressViewStyle(CircularProgressViewStyle())
            .padding()
        }
      } else {
        Text("Enter LinkedIn Job URL")
        TextField("https://www.linkedin.com/jobs/view/3951765732", text: $urlText)
          .textFieldStyle(RoundedBorderTextFieldStyle())
          .padding()

        HStack {
          Button("Cancel") {
            isPresented = false
          }
          Spacer()
          Button("Scrape URL") {
            Task {
              await handleNewApp()
            }
          }
        }
      }
    }
    .padding()
  }

  private func handleNewApp() async {
    guard let url = URL(string: urlText), url.host == "www.linkedin.com" else {
      // Handle invalid URL
      return
    }
    isLoading = true
    if let jobID = url.pathComponents.last {
      await fetchJobDetails(jobID: jobID)
    }
  }

  private func fetchJobDetails(jobID: String) async {
    let apiKey = scrapingDogApiKey
    let requestURL = "https://api.scrapingdog.com/linkedinjobs?api_key=\(apiKey)&job_id=\(jobID)"

    guard let url = URL(string: requestURL) else { return }

    do {
      print(requestURL)
      let (data, response) = try await URLSession.shared.data(from: url)

      if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        // Handle HTTP error (non-200 status code)
        print("HTTP error: \(httpResponse.statusCode)")
        isLoading = false
        return
      }

      let jobDetails = try JSONDecoder().decode([JobApp].self, from: data)
      if let jobDetail = jobDetails.first {
        jobAppStore.selectedApp = jobAppStore.addJobApp(jobDetail)
        isPresented = false
      }
    } catch {
      // Handle network or decoding error
      print("Error: \(error)")
    }

    isLoading = false
  }
}
