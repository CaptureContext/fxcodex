import Foundation

public struct SemanticVersion: Comparable, Codable, CustomStringConvertible, Sendable {
	public let major: Int
	public let minor: Int
	public let patch: Int
	public let prereleaseIdentifiers: [String]
	public let buildMetadataIdentifiers: [String]

	public var description: String {
		var value: String = "\(self.major).\(self.minor).\(self.patch)"
		if !self.prereleaseIdentifiers.isEmpty {
			value += "-\(self.prereleaseIdentifiers.joined(separator: "."))"
		}
		if !self.buildMetadataIdentifiers.isEmpty {
			value += "+\(self.buildMetadataIdentifiers.joined(separator: "."))"
		}
		return value
	}

	public var isPrerelease: Bool {
		!self.prereleaseIdentifiers.isEmpty
	}

	public init(
		major: Int,
		minor: Int,
		patch: Int,
		prereleaseIdentifiers: [String] = [],
		buildMetadataIdentifiers: [String] = []
	) {
		self.major = major
		self.minor = minor
		self.patch = patch
		self.prereleaseIdentifiers = prereleaseIdentifiers
		self.buildMetadataIdentifiers = buildMetadataIdentifiers
	}

	public init?(_ description: String) {
		let value: String = description.first == "v"
			? String(description.dropFirst())
			: description
		let buildComponents: [Substring] = value.split(
			separator: "+",
			maxSplits: 1,
			omittingEmptySubsequences: false
		)
		guard !buildComponents[0].isEmpty else { return nil }

		let versionComponents: [Substring] = buildComponents[0].split(
			separator: "-",
			maxSplits: 1,
			omittingEmptySubsequences: false
		)
		let numberComponents: [Substring] = versionComponents[0].split(
			separator: ".",
			omittingEmptySubsequences: false
		)
		guard
			numberComponents.count == 3,
			let major = Self.parseNumber(numberComponents[0]),
			let minor = Self.parseNumber(numberComponents[1]),
			let patch = Self.parseNumber(numberComponents[2])
		else { return nil }

		let prereleaseIdentifiers: [String]
		if versionComponents.count == 2 {
			guard let identifiers = Self.parseIdentifiers(
				versionComponents[1],
				numericLeadingZerosAllowed: false
			) else { return nil }
			prereleaseIdentifiers = identifiers
		} else {
			prereleaseIdentifiers = []
		}

		let buildMetadataIdentifiers: [String]
		if buildComponents.count == 2 {
			guard let identifiers = Self.parseIdentifiers(
				buildComponents[1],
				numericLeadingZerosAllowed: true
			) else { return nil }
			buildMetadataIdentifiers = identifiers
		} else {
			buildMetadataIdentifiers = []
		}

		self.init(
			major: major,
			minor: minor,
			patch: patch,
			prereleaseIdentifiers: prereleaseIdentifiers,
			buildMetadataIdentifiers: buildMetadataIdentifiers
		)
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.singleValueContainer()
		let value: String = try container.decode(String.self)
		guard let version = Self(value) else {
			throw DecodingError.dataCorruptedError(
				in: container,
				debugDescription: "Invalid semantic version '\(value)'."
			)
		}
		self = version
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(self.description)
	}

	public static func == (lhs: Self, rhs: Self) -> Bool {
		lhs.major == rhs.major
		&& lhs.minor == rhs.minor
		&& lhs.patch == rhs.patch
		&& lhs.prereleaseIdentifiers == rhs.prereleaseIdentifiers
	}

	public static func < (lhs: Self, rhs: Self) -> Bool {
		let lhsNumbers: [Int] = [lhs.major, lhs.minor, lhs.patch]
		let rhsNumbers: [Int] = [rhs.major, rhs.minor, rhs.patch]
		if lhsNumbers != rhsNumbers {
			return lhsNumbers.lexicographicallyPrecedes(rhsNumbers)
		}

		if lhs.prereleaseIdentifiers.isEmpty {
			return false
		}
		if rhs.prereleaseIdentifiers.isEmpty {
			return true
		}

		for (lhsIdentifier, rhsIdentifier) in zip(
			lhs.prereleaseIdentifiers,
			rhs.prereleaseIdentifiers
		) {
			guard lhsIdentifier != rhsIdentifier else { continue }
			let lhsNumber: Int? = Int(lhsIdentifier)
			let rhsNumber: Int? = Int(rhsIdentifier)
			switch (lhsNumber, rhsNumber) {
			case let (.some(lhsNumber), .some(rhsNumber)):
				return lhsNumber < rhsNumber

			case (.some, .none):
				return true

			case (.none, .some):
				return false

			case (.none, .none):
				return lhsIdentifier < rhsIdentifier
			}
		}

		return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
	}
}

extension SemanticVersion {
	private static func parseNumber(_ value: Substring) -> Int? {
		guard
			!value.isEmpty,
			value.allSatisfy(\.isNumber),
			value == "0" || value.first != "0"
		else { return nil }
		return Int(value)
	}

	private static func parseIdentifiers(
		_ value: Substring,
		numericLeadingZerosAllowed: Bool
	) -> [String]? {
		let identifiers: [Substring] = value.split(
			separator: ".",
			omittingEmptySubsequences: false
		)
		guard !identifiers.isEmpty else { return nil }
		for identifier in identifiers {
			guard
				!identifier.isEmpty,
				identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
			else { return nil }
			if
				!numericLeadingZerosAllowed,
				identifier.allSatisfy(\.isNumber),
				identifier.count > 1,
				identifier.first == "0"
			{
				return nil
			}
		}
		return identifiers.map(String.init)
	}
}
