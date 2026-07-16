import Foundation
import Testing
@testable import FXCodexClient

@Suite("fxcodex JSON coding")
struct FXCodexJSONCodingTests {
	private struct Payload: Codable, Equatable {
		let apiVersion: Int
		let applicationURL: URL
		let processID: Int32
	}

	@Test("Encodes property names as lower snake case")
	func lowerSnakeCase() throws {
		let payload: Payload = .init(
			apiVersion: 1,
			applicationURL: URL(filePath: "/Applications/Codex.app"),
			processID: 42
		)
		let data: Data = try FXCodexJSONCoding.encoder().encode(payload)
		let object: [String: Any] = try #require(
			JSONSerialization.jsonObject(with: data) as? [String: Any]
		)

		#expect(Set(object.keys) == [
			"api_version",
			"application_url",
			"process_id",
		])
	}

}
