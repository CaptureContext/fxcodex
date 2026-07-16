import Foundation

public struct CodexApplicationRenameResult: Codable, Equatable, Sendable {
	public enum Outcome: String, Codable, Sendable {
		case renamed
		case alreadyNamed = "already-named"
		case conflict
	}

	public let outcome: Outcome
	public let requestedName: CodexApplicationName
	public let applicationURL: URL
	public let otherApplicationURL: URL?

	public init(
		outcome: Outcome,
		requestedName: CodexApplicationName,
		applicationURL: URL,
		otherApplicationURL: URL?
	) {
		self.outcome = outcome
		self.requestedName = requestedName
		self.applicationURL = applicationURL
		self.otherApplicationURL = otherApplicationURL
	}
}
