import Foundation
import Testing
@testable
import FXCodexClient

@Suite("Semantic version")
struct SemanticVersionTests {
	@Test("Parses and renders complete semantic versions")
	func parsing() async throws {
		let version: SemanticVersion = try #require(.init("v1.2.3-beta.2+build.7"))

		#expect(version.major == 1)
		#expect(version.minor == 2)
		#expect(version.patch == 3)
		#expect(version.prereleaseIdentifiers == ["beta", "2"])
		#expect(version.buildMetadataIdentifiers == ["build", "7"])
		#expect(version.description == "1.2.3-beta.2+build.7")
	}

	@Test("Rejects invalid versions")
	func validation() async throws {
		#expect(SemanticVersion("1.2") == nil)
		#expect(SemanticVersion("01.2.3") == nil)
		#expect(SemanticVersion("1.2.3-beta.01") == nil)
		#expect(SemanticVersion("1.2.3-") == nil)
	}

	@Test("Orders prereleases according to semantic version precedence")
	func ordering() async throws {
		let versions: [SemanticVersion] = try [
			"1.0.0",
			"1.0.0-beta.11",
			"1.0.0-alpha",
			"2.0.0",
			"1.0.0-beta.2",
		].map { try #require(SemanticVersion($0)) }

		#expect(versions.sorted().map(\.description) == [
			"1.0.0-alpha",
			"1.0.0-beta.2",
			"1.0.0-beta.11",
			"1.0.0",
			"2.0.0",
		])
	}

	@Test("Codable representation is a version string")
	func coding() async throws {
		let version: SemanticVersion = try #require(.init("1.2.3"))
		let data: Data = try JSONEncoder().encode(version)

		#expect(String(data: data, encoding: .utf8) == "\"1.2.3\"")
		#expect(try JSONDecoder().decode(SemanticVersion.self, from: data) == version)
	}
}
