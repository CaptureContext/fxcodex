import Foundation

public struct FXCodexStatus: Codable, Equatable, Sendable {
	public let currentWorkspace: String
	public let currentWorkspaceID: WorkspaceID
	public let supportDirectoryURL: URL
	public let applicationURL: URL?
	public let preferences: FXCodexPreferences
	public let workspaces: [WorkspaceStatus]
	public let raycastApplications: [RaycastApplicationStatus]
	public let raycastScriptCommands: RaycastScriptCommandStatus

	public init(
		currentWorkspace: String,
		currentWorkspaceID: WorkspaceID,
		supportDirectoryURL: URL,
		applicationURL: URL?,
		preferences: FXCodexPreferences,
		workspaces: [WorkspaceStatus],
		raycastApplications: [RaycastApplicationStatus],
		raycastScriptCommands: RaycastScriptCommandStatus
	) {
		self.currentWorkspace = currentWorkspace
		self.currentWorkspaceID = currentWorkspaceID
		self.supportDirectoryURL = supportDirectoryURL
		self.applicationURL = applicationURL
		self.preferences = preferences
		self.workspaces = workspaces
		self.raycastApplications = raycastApplications
		self.raycastScriptCommands = raycastScriptCommands
	}
}
