internal struct WorkspaceNamesOutput: Encodable {
	internal let workspaceNames: [String]

	internal init(
		workspaceNames: [String]
	) {
		self.workspaceNames = workspaceNames
	}
}
