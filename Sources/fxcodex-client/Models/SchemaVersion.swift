import Foundation

public struct SchemaVersion: Codable, Comparable, CustomStringConvertible, Hashable, Sendable {
	public static let v1_0: Self = .init(major: 1, minor: 0)
	public static let v2_0: Self = .init(major: 2, minor: 0)

	public let major: Int
	public let minor: Int

	public var description: String { "\(self.major).\(self.minor)" }

	public init(major: Int, minor: Int) {
		precondition(major >= 0 && minor >= 0)
		self.major = major
		self.minor = minor
	}

	public init?(_ description: String) {
		let components = description.split(separator: ".", omittingEmptySubsequences: false)

		guard
			components.count == 2,
			let major = Self.parse(components[0]),
			let minor = Self.parse(components[1])
		else { return nil }

		self.init(major: major, minor: minor)
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		let value = try container.decode(String.self)
		guard let version = Self(value) else {
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "Invalid schema version \(value). Expected major.minor."
			)
		}
		self = version
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(self.description)
	}

	public static func < (lhs: Self, rhs: Self) -> Bool {
		(lhs.major, lhs.minor) < (rhs.major, rhs.minor)
	}

	private static func parse(_ component: Substring) -> Int? {
		guard
			!component.isEmpty,
			component.allSatisfy(\.isNumber),
			component == "0" || component.first != "0"
		else { return nil }

		return Int(component)
	}
}
