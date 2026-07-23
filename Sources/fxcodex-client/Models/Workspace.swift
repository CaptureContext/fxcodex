import Foundation

public enum WorkspaceKind: String, Codable, Sendable {
	case primary
	case managed
}

public struct Workspace: Codable, Equatable, Sendable {
	public static let primaryName: String = "primary"

	public let id: WorkspaceID
	public let name: String
	public let kind: WorkspaceKind
	public let rootURL: URL?
	public let codexHomeURL: URL?
	public let userDataURL: URL?
	public var integrations: [String: CodableValue]

	public init(
		id: WorkspaceID = .generate(),
		name: String,
		kind: WorkspaceKind,
		rootURL: URL?,
		codexHomeURL: URL?,
		userDataURL: URL?,
		integrations: [String: CodableValue] = [:]
	) {
		self.id = id
		self.name = name
		self.kind = kind
		self.rootURL = rootURL
		self.codexHomeURL = codexHomeURL
		self.userDataURL = userDataURL
		self.integrations = integrations
	}
}
