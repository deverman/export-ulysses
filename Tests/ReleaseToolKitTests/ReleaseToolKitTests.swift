import Foundation
import XCTest
@testable import ReleaseToolKit

final class ReleaseToolKitTests: XCTestCase {
    func testArtifactNameIsStable() throws {
        let config = try DirectReleaseConfiguration(version: "2.3.4", architecture: "arm64")
        XCTAssertEqual(config.artifactName, "export-ulysses-2.3.4-macos26-arm64")
    }

    func testRejectsUnsupportedArchitecture() {
        XCTAssertThrowsError(try DirectReleaseConfiguration(version: "1.0.0", architecture: "i386")) { error in
            XCTAssertEqual(error as? ReleaseConfigurationError, .invalidArchitecture("i386"))
        }
    }

    func testNotarizationCredentialsAreOptionalAsACompleteSet() throws {
        XCTAssertNil(try NotarizationCredentials.resolve(environment: [:]))
        let credentials = try XCTUnwrap(NotarizationCredentials.resolve(environment: [
            "APPLE_ID": "person@example.com",
            "APPLE_TEAM_ID": "TEAM",
            "APPLE_APP_PASSWORD": "secret"
        ]))
        XCTAssertEqual(credentials.teamID, "TEAM")
    }

    func testRejectsPartialNotarizationConfiguration() {
        XCTAssertThrowsError(try NotarizationCredentials.resolve(environment: ["APPLE_ID": "person@example.com"])) { error in
            XCTAssertEqual(
                error as? ReleaseConfigurationError,
                .partialNotarizationEnvironment(["APPLE_TEAM_ID", "APPLE_APP_PASSWORD"])
            )
        }
    }

    func testRepositoryRootValidationIsActionable() {
        let missing = URL(fileURLWithPath: "/definitely/not/export-ulysses")
        XCTAssertThrowsError(try RepositoryRoot.validate(missing)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Package.swift"))
        }
    }
}
