public struct WorkspaceStatus: Codable, Equatable, Sendable {
	public let workspace: Workspace
	public let isCurrent: Bool
	public let processID: Int32?

	public init(
		workspace: Workspace,
		isCurrent: Bool,
		processID: Int32?
	) {
		self.workspace = workspace
		self.isCurrent = isCurrent
		self.processID = processID
	}
}
