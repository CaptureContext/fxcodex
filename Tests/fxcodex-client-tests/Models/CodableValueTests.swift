import Foundation
import Testing
@testable import FXCodexClient

@Suite("Codable value")
struct CodableValueTests {
	@Test("Encodes and decodes the same JSON representation")
	func roundTrip() async throws {
		let value: CodableValue = .dictionary([
			"integer": .int(42),
			"float": .float(2.5),
			"string": .string("Codex"),
			"boolean": .bool(true),
			"array": .array([
				.int(-1),
				.string("nested"),
			]),
		])
		let data: Data = try JSONEncoder().encode(value)
		let decodedValue: CodableValue = try JSONDecoder().decode(
			CodableValue.self,
			from: data
		)

		#expect(decodedValue == value)
	}

	@Test("Decodes every supported JSON value recursively")
	func supportedValues() async throws {
		let data: Data = try #require(#"""
		{
			"integer": 42,
			"float": 2.5,
			"string": "Codex",
			"boolean": true,
			"array": [1, false, "value"],
			"dictionary": { "nested": -3 }
		}
		"""#.data(using: .utf8))
		let value: CodableValue = try JSONDecoder().decode(
			CodableValue.self,
			from: data
		)

		#expect(value == .dictionary([
			"integer": .int(42),
			"float": .float(2.5),
			"string": .string("Codex"),
			"boolean": .bool(true),
			"array": .array([
				.int(1),
				.bool(false),
				.string("value"),
			]),
			"dictionary": .dictionary([
				"nested": .int(-3),
			]),
		]))
	}

	@Test("Rejects null values")
	func nullValue() async throws {
		let data: Data = try #require("null".data(using: .utf8))
		#expect(throws: DecodingError.self) {
			try JSONDecoder().decode(
				CodableValue.self,
				from: data
			)
		}
	}
}
