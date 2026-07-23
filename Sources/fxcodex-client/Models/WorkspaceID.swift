import Foundation

public struct WorkspaceID: Codable, Comparable, CustomStringConvertible, Hashable, Sendable {
	public let rawValue: String

	public var description: String { self.rawValue }

	public init?(_ rawValue: String) {
		guard
			let uuid = UUID(uuidString: rawValue),
			uuid.uuidString.lowercased() == rawValue
		else { return nil }

		self.rawValue = rawValue
	}

	public static func generate() -> Self {
		Self(UUID().uuidString.lowercased())!
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		let value = try container.decode(String.self)
		guard let id = Self(value) else {
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "Invalid lowercase workspace UUID \(value)."
			)
		}
		self = id
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(self.rawValue)
	}

	public static func < (lhs: Self, rhs: Self) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}
