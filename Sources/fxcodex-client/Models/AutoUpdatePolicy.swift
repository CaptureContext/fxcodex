public enum AutoUpdatePolicy: Equatable, Sendable {
	case disabled
	case patch(from: SemanticVersion)
	case minor(from: SemanticVersion)
	case major(from: SemanticVersion)
	case latest(from: SemanticVersion)
}

extension AutoUpdatePolicy: Codable {
	private enum CodingKeys: String, CodingKey {
		case channel
		case from
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let channel: String = try container.decode(String.self, forKey: .channel)
		let from: SemanticVersion? = try container.decodeIfPresent(
			SemanticVersion.self,
			forKey: .from
		)

		switch channel {
		case "disabled":
			self = .disabled

		case "patch":
			self = .patch(from: try Self.requireMinimumVersion(from, in: container))

		case "minor":
			self = .minor(from: try Self.requireMinimumVersion(from, in: container))

		case "major":
			self = .major(from: try Self.requireMinimumVersion(from, in: container))

		case "latest":
			self = .latest(from: from ?? .init(major: 0, minor: 0, patch: 0))

		default:
			throw DecodingError.dataCorruptedError(
				forKey: .channel,
				in: container,
				debugDescription: "Unknown automatic update channel '\(channel)'."
			)
		}
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		switch self {
		case .disabled:
			try container.encode("disabled", forKey: .channel)

		case let .patch(from):
			try container.encode("patch", forKey: .channel)
			try container.encode(from, forKey: .from)

		case let .minor(from):
			try container.encode("minor", forKey: .channel)
			try container.encode(from, forKey: .from)

		case let .major(from):
			try container.encode("major", forKey: .channel)
			try container.encode(from, forKey: .from)

		case let .latest(from):
			try container.encode("latest", forKey: .channel)
			try container.encode(from, forKey: .from)
		}
	}

	private static func requireMinimumVersion(
		_ version: SemanticVersion?,
		in container: KeyedDecodingContainer<CodingKeys>
	) throws -> SemanticVersion {
		guard let version else {
			throw DecodingError.keyNotFound(
				CodingKeys.from,
				.init(
					codingPath: container.codingPath,
					debugDescription: "An automatic update constraint requires a minimum version."
				)
			)
		}
		return version
	}
}

extension AutoUpdatePolicy {
	public var description: String {
		switch self {
		case .disabled:
			"disabled"

		case let .patch(from):
			"patch from \(from)"

		case let .minor(from):
			"minor from \(from)"

		case let .major(from):
			"major from \(from)"

		case let .latest(from):
			"latest from \(from)"
		}
	}

	var updateChannel: UpdateChannel? {
		switch self {
		case .disabled: nil
		case .patch: .patch
		case .minor: .minor
		case .major: .major
		case .latest: .latest
		}
	}

	var minimumVersion: SemanticVersion? {
		switch self {
		case .disabled: nil
		case let .patch(from): from
		case let .minor(from): from
		case let .major(from): from
		case let .latest(from): from
		}
	}
}
