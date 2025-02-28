//
//  ResumeApiRefresh.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/7/24.
//

import Foundation

func apiGenerateResFromJson(jsonPath: URL, resume: Resume, completion: @escaping (Bool) -> Void) {
    // URL of the API endpoint
    guard let url = URL(string: "https://resume.physicscloud.net/build-resume-file") else {
        print("Invalid URL")
        completion(false)
        return
    }

    // Ensure the style parameter exists
    guard let style = resume.model?.style else {
        print("Style parameter is missing")
        completion(false)
        return
    }

    // Create a URLRequest
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    // Set the API key in the headers
    request.addValue("b0b307e1-6eb4-41d9-8c1f-278c254351d3", forHTTPHeaderField: "x-api-key")

    // Prepare the file data to be uploaded
    let boundary = UUID().uuidString
    let fileData: Data
    do {
        fileData = try Data(contentsOf: jsonPath)
    } catch {
        print("Error loading JSON file: \(error)")
        completion(false)
        return
    }

    // Set the Content-Type to multipart/form-data
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    // Create multipart form body
    var body = Data()

    // Append style parameter
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"style\"\r\n\r\n".data(using: .utf8)!)
    body.append("\(style)\r\n".data(using: .utf8)!)

    // Append file data
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"resumeFile\"; filename=\"\(jsonPath.lastPathComponent)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n".data(using: .utf8)!)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)

    // Set the body
    request.httpBody = body

    // Create the URLSession and upload the file
    let task = URLSession.shared.dataTask(with: request) { data, _, error in
        if let error = error {
            print("Error: \(error)")
            completion(false)
            return
        }

        guard let data = data else {
            print("No data received")
            completion(false)
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                let pdfUrl = json["pdfUrl"] as? String
                let resumeText = json["resumeText"] as? String

                DispatchQueue.main.async {
                    // Store text data
                    if let resumeText = resumeText {
                        resume.textRes = resumeText
                    }

                    // Fetch and store PDF data
                    if let pdfUrl = pdfUrl {
                        downloadResPDF(from: pdfUrl, resume: resume, completion: completion)
                    } else {
                        completion(false)
                    }
                }
            } else {
                print("Invalid JSON format")
                completion(false)
            }
        } catch {
            print("Error parsing JSON: \(error)")
            completion(false)
        }
    }

    task.resume()
}

func downloadResPDF(from urlString: String, resume: Resume, completion: @escaping (Bool) -> Void) {
    guard let url = URL(string: urlString) else {
        print("Invalid URL")
        completion(false)
        return
    }

    // Create a URLSession data task to download the PDF
    let task = URLSession.shared.dataTask(with: url) { data, _, error in
        if let error = error {
            print("Error downloading PDF: \(error)")
            completion(false)
            return
        }

        guard let data = data else {
            print("No PDF data received")
            completion(false)
            return
        }

        DispatchQueue.main.async {
            resume.pdfData = data
            print("PDF successfully stored in resume.pdfData (\(data.count) bytes)")
            completion(true)
        }
    }

    task.resume()
}
