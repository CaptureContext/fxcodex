internal struct OpenWorkspaceOutput: Encodable {
	internal let workspaceName: String
	internal let processID: Int32

	internal init(
		workspaceName: String,
		processID: Int32
	) {
		self.workspaceName = workspaceName
		self.processID = processID
	}
}
