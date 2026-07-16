public struct UpdateResult: Codable, Equatable, Sendable {
	public enum Outcome: String, Codable, Sendable {
		case updated
		case alreadyCurrent = "already-current"
	}

	public let outcome: Outcome
	public let previousVersion: SemanticVersion
	public let version: SemanticVersion

	public init(
		outcome: Outcome,
		previousVersion: SemanticVersion,
		version: SemanticVersion
	) {
		self.outcome = outcome
		self.previousVersion = previousVersion
		self.version = version
	}
}
