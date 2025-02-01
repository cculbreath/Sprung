//
//  ResumeApiRefresh.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/7/24.
//

import Foundation

func apiGenerateResFromJson(jsonPath: URL, completion: @escaping (String?, String?) -> Void) {
    // URL of the API endpoint
    guard let url = URL(string: "https://resume.physicscloud.net/build-resume-file") else {
        print("Invalid URL")
        completion(nil, nil)
        return
    }

    // Create a URLRequest
    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    // Set the API key in the headers
    request.addValue("b0b307e1-6eb4-41d9-8c1f-278c254351d3", forHTTPHeaderField: "x-api-key")

    // Prepare the file data to be uploaded
    let boundary = UUID().uuidString
    let fileData = try! Data(contentsOf: jsonPath)

    // Set the Content-Type to multipart/form-data
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    // Create multipart form body
    var body = Data()
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"resumeFile\"; filename=\"\(jsonPath.lastPathComponent)\"\r\n".data(using: .utf8)!)
    body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n".data(using: .utf8)!)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)

    // Set the body
    request.httpBody = body

    // Create the URLSession and upload the file
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("Error: \(error)")
            completion(nil, nil)
            return
        }

        if let response = response as? HTTPURLResponse {
            print("Response status code: \(response.statusCode)")
        }

        guard let data = data else {
            print("No data received")
            completion(nil, nil)
            return
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                let pdfUrl = json["pdfUrl"] as? String
                let resumeText = json["resumeText"] as? String
                completion(pdfUrl, resumeText)
            } else {
                print("Invalid JSON format")
                completion(nil, nil)
            }
        } catch {
            print("Error parsing JSON: \(error)")
            completion(nil, nil)
        }
    }

    task.resume()
}

func downloadResPDF(from urlString: String, completion: @escaping (URL?) -> Void) {
    guard let url = URL(string: urlString) else {
        print("Invalid URL")
        completion(nil)
        return
    }

    // Create a URLSession data task to download the PDF
    let task = URLSession.shared.downloadTask(with: url) { tempFileURL, _, error in
        if let error = error {
            print("Error downloading PDF: \(error)")
            completion(nil)
            return
        }

        guard let tempFileURL = tempFileURL else {
            print("No file URL")
            completion(nil)
            return
        }

        // Move the file to a permanent location
        let fileManager = FileManager.default
        let destinationURL = FileHandler.pdfUrl()

        do {
            // If file exists, remove it first
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            // Move the file from temp location to permanent destination
            try fileManager.moveItem(at: tempFileURL, to: destinationURL)
            print("File downloaded to: \(destinationURL)")
            completion(destinationURL)
        } catch {
            print("Error saving file: \(error)")
            completion(nil)
        }
    }

    task.resume()
}
