import Foundation
import Testing
@testable import MacDownCore

private func release(
    _ tag: String,
    prerelease: Bool = false,
    draft: Bool = false
) -> Release {
    Release(
        tagName: tag,
        name: tag,
        htmlURL: URL(string: "https://example.com/releases/\(tag)")!,
        body: "notes",
        isPrerelease: prerelease,
        isDraft: draft
    )
}

@Suite("Semantic versions")
struct SemanticVersionTests {

    @Test("Parses a plain version")
    func plain() {
        #expect(SemanticVersion("1.2.3")?.description == "1.2.3")
    }

    @Test("Tolerates a leading v")
    func leadingV() {
        #expect(SemanticVersion("v0.1.0")?.description == "0.1.0")
    }

    @Test("Drops a pre-release suffix")
    func prereleaseSuffix() {
        #expect(SemanticVersion("1.2.0-beta.1")?.description == "1.2.0")
    }

    @Test("Rejects text that isn't a version")
    func rejectsGarbage() {
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("nightly") == nil)
    }

    @Test("Compares numerically, not as text")
    func numericOrdering() {
        // The case string comparison gets wrong.
        #expect(SemanticVersion("0.10.0")! > SemanticVersion("0.9.0")!)
        #expect(SemanticVersion("1.0.0")! > SemanticVersion("0.99.99")!)
        #expect(SemanticVersion("2.0.0")! > SemanticVersion("1.999.0")!)
    }

    @Test("Missing components count as zero")
    func missingComponents() {
        #expect(SemanticVersion("1.2")! == SemanticVersion("1.2.0")!)
        #expect(SemanticVersion("1")! < SemanticVersion("1.0.1")!)
    }

    @Test("Equal versions are neither greater nor less")
    func equality() {
        let a = SemanticVersion("1.2.3")!
        let b = SemanticVersion("1.2.3")!
        #expect(a == b)
        #expect(!(a < b))
        #expect(!(b < a))
    }
}

@Suite("Update comparison")
struct UpdateComparisonTests {

    @Test("A newer release is offered")
    func newerIsOffered() {
        let result = UpdateChecker.compare(release: release("v0.2.0"), against: "0.1.0")
        #expect(result == .updateAvailable(release("v0.2.0")))
    }

    @Test("The same version reports up to date")
    func sameVersion() {
        #expect(
            UpdateChecker.compare(release: release("v0.1.0"), against: "0.1.0")
                == .upToDate(current: "0.1.0")
        )
    }

    @Test("An older release is never offered")
    func olderIsIgnored() {
        #expect(
            UpdateChecker.compare(release: release("v0.0.9"), against: "0.1.0")
                == .upToDate(current: "0.1.0")
        )
    }

    @Test("Pre-releases and drafts are not offered")
    func skipsPrereleaseAndDraft() {
        #expect(
            UpdateChecker.compare(release: release("v9.0.0", prerelease: true), against: "0.1.0")
                == .upToDate(current: "0.1.0")
        )
        #expect(
            UpdateChecker.compare(release: release("v9.0.0", draft: true), against: "0.1.0")
                == .upToDate(current: "0.1.0")
        )
    }

    @Test("An unparseable tag is treated as no update")
    func unparseableTag() {
        #expect(
            UpdateChecker.compare(release: release("nightly"), against: "0.1.0")
                == .upToDate(current: "0.1.0")
        )
    }

    @Test("A dev build is not nagged about releases it can't compare to")
    func devBuild() {
        // build-app.sh stamps 0.0.0-dev when there's no tag.
        let result = UpdateChecker.compare(release: release("v0.1.0"), against: "0.0.0-dev")
        #expect(result == .updateAvailable(release("v0.1.0")), "0.0.0 really is older")
    }
}

@Suite("Update fetching")
struct UpdateFetchingTests {

    private func checker(
        json: String,
        status: Int = 200
    ) -> UpdateChecker {
        UpdateChecker(repository: "example/repo") { url in
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (Data(json.utf8), response)
        }
    }

    @Test("Decodes the fields we care about from a release payload")
    func decodesPayload() async throws {
        let json = """
        {
          "tag_name": "v1.4.0",
          "name": "MacDown 1.4.0",
          "html_url": "https://github.com/example/repo/releases/tag/v1.4.0",
          "body": "Fixes things.",
          "prerelease": false,
          "draft": false,
          "unrelated_field": 123
        }
        """
        let result = try await checker(json: json).check(currentVersion: "1.0.0")
        guard case .updateAvailable(let release) = result else {
            Issue.record("expected an update, got \(result)")
            return
        }
        #expect(release.tagName == "v1.4.0")
        #expect(release.name == "MacDown 1.4.0")
        #expect(release.body == "Fixes things.")
    }

    @Test("Reports up to date when already on the newest version")
    func upToDate() async throws {
        let json = """
        {"tag_name": "v1.0.0", "html_url": "https://example.com", "prerelease": false, "draft": false}
        """
        let result = try await checker(json: json).check(currentVersion: "1.0.0")
        #expect(result == .upToDate(current: "1.0.0"))
    }

    @Test("A non-success status is surfaced as an error")
    func badStatus() async {
        let checker = checker(json: "{}", status: 503)
        await #expect(throws: UpdateChecker.Failure.self) {
            _ = try await checker.check(currentVersion: "1.0.0")
        }
    }

    @Test("Builds the right API URL")
    func apiURL() {
        let checker = UpdateChecker(repository: "mfbergmann/macdown-swift")
        #expect(
            checker.latestReleaseURL.absoluteString
                == "https://api.github.com/repos/mfbergmann/macdown-swift/releases/latest"
        )
    }
}
