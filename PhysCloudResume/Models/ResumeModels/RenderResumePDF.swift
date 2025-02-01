import Foundation

class PdfResume {
    static func render(res _: Resume) {
        // Step 1: Get the paths for the JSON input, PDF output, and theme
        if !FileHandler.fontsDone {
//      FileHandler.copyFontsToAppSupport()
            FileHandler.fontsDone = true
        }
        let process = Process()

        let jsonPath: URL = FileHandler.jsonUrl()
        let pdfPath: URL = FileHandler.pdfUrl()
        let templatePath: URL = FileHandler.pdfUrl(filename: "rendered-resume.pdf.html")

        // Locate the typewriter theme directory in the bundle
        guard
            let themeDirectory = Bundle.main.url(
                forResource: "typewriter", withExtension: nil, subdirectory: "scripts"
            )

        else {
            print("Theme directory not found")
            return
        }
        process.currentDirectoryURL = themeDirectory
        // Get all files and directories in the theme (this step is optional for listing files)
//    let files = listFilesInThemeDirectory(at: themeDirectory)
        //    print("Theme files: \(files)")  // You can remove this line if you don't need to list files

        // Step 2: Find the HackMyResume utility in the bundle
        guard
            let utilityURL = Bundle.main.url(
                forResource: "HackMyResume", withExtension: nil, subdirectory: "scripts"
            )
        else {
            print("HackMyResume executable not found in the bundle")
            return
        }

        // Step 3: Create a Process to execute the utility
        process.executableURL = utilityURL

        // Step 4: Pass the correct arguments
        process.arguments = [
            "build",
            jsonPath.path, // Path to the input JSON file
            "to",
            templatePath.path, // Path to the output PDF file
            "-t", themeDirectory.path, // Pass the theme directory
            "-p", "none", // Specify the PDF generator (weasyprint)
            "-d", // Enable debugging
        ]

        // Step 5: Set up a pipe to capture standard output
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            // Step 6: Execute the process
            try process.run()

            // Wait until the process is done
            process.waitUntilExit()

            // Step 7: Read and print the output if needed
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("Output: \(output)")
            }
            htmlToPdf(sourceUrl: templatePath, destUrl: pdfPath)
        } catch {
            print("Error executing the utility: \(error)")
        }
    }

    // Helper function to list files in a directory (optional)
    static func listFilesInThemeDirectory(at directory: URL) -> [URL] {
        let fileManager = FileManager.default
        var urls = [URL]()

        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                urls.append(url)
            }
        }

        return urls
    }

    static func htmlToPdf(sourceUrl: URL, destUrl: URL) {
        let process = Process()
        print("html")
        guard
            let utilityURL = Bundle.main.url(
                forResource: "weasyprint", withExtension: nil, subdirectory: "weasy-dist"
            )
        else {
            print("weasyprint executable not found in the bundle")
            return
        }
        process.executableURL = utilityURL
        process.arguments = [
            sourceUrl.path,
            destUrl.path,
        ]

        // Step 5: Set up a pipe to capture standard output
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            // Step 6: Execute the process
            try process.run()

            // Wait until the process is done
            process.waitUntilExit()

            // Step 7: Read and print the output if needed
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                print("Output: \(output)")
            }
        } catch {
            print("Error executing the utility: \(error)")
        }
    }
}
