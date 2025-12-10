import XCTest
@testable import Sprung

final class LinkedInScraperTests: XCTestCase {

    func testParseLinkedInJobListing_StandardLayout() throws {
        // Given a sample HTML snippet mimicking a standard LinkedIn job page
        let html = """
        <html>
        <body>
            <div class="job-details-jobs-unified-top-card__job-title">
                <h1>Senior Software Engineer</h1>
            </div>
            <div class="job-details-jobs-unified-top-card__company-name">
                <a href="/company/apple">Apple</a>
            </div>
            <div class="job-details-jobs-unified-top-card__primary-description-container">
                <span class="t-black--light">Cupertino, CA · On-site</span>
            </div>
            <div id="job-details">
                <span>
                    We are looking for a Swift expert to build the future of iOS.
                    Requirements: 5+ years of experience.
                </span>
            </div>
            <a class="jobs-apply-button" href="https://www.linkedin.com/jobs/apply/12345">
                Easy Apply
            </a>
        </body>
        </html>
        """

        // When parsing the HTML
        let jobApp = JobApp.parseLinkedInJobListing(html: html, url: "https://www.linkedin.com/jobs/view/12345")

        // Then verify the extracted fields
        XCTAssertNotNil(jobApp, "JobApp should be successfully parsed")
        XCTAssertEqual(jobApp?.jobPosition, "Senior Software Engineer")
        XCTAssertEqual(jobApp?.companyName, "Apple")
        // Location extraction might include dots/extra chars depending on implementation logic
        XCTAssertTrue(jobApp?.jobLocation.contains("Cupertino") ?? false)
        XCTAssertTrue(jobApp?.jobDescription.contains("Swift expert") ?? false)
        XCTAssertNotNil(jobApp?.jobApplyLink)
    }

    func testParseLinkedInJobListing_2024Layout() throws {
        // Given a sample HTML snippet mimicking the 2024 LinkedIn layout
        let html = """
        <html>
        <body>
            <h1 class="job-details-module__title">
                Machine Learning Engineer
            </h1>
            <div class="job-details-module__company-name">
                OpenAI
            </div>
            <div class="jobs-unified-top-card__bullet">
                San Francisco, CA
            </div>
            <div class="jobs-description-content__text">
                Build AGI with us.
            </div>
        </body>
        </html>
        """

        // When parsing the HTML
        let jobApp = JobApp.parseLinkedInJobListing(html: html, url: "https://www.linkedin.com/jobs/view/67890")

        // Then verify the extracted fields
        XCTAssertNotNil(jobApp, "JobApp should be successfully parsed with 2024 selectors")
        XCTAssertEqual(jobApp?.jobPosition, "Machine Learning Engineer")
        XCTAssertEqual(jobApp?.companyName, "OpenAI")
        XCTAssertEqual(jobApp?.jobLocation, "San Francisco, CA")
    }

    func testParseLinkedInJobListing_MissingTitle() throws {
        // Given HTML with missing critical fields
        let html = """
        <html><body><div>No title here</div></body></html>
        """

        // When parsing
        let jobApp = JobApp.parseLinkedInJobListing(html: html, url: "https://example.com")

        // Then it should return nil or handle gracefully
        XCTAssertNil(jobApp, "Should return nil when critical information is missing")
    }
}
