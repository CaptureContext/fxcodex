import Foundation
import FXCodexClient

internal struct StatusOutput: Encodable {
	internal let currentWorkspace: String
	internal let supportDirectoryURL: URL
	internal let applicationURL: URL?
	internal let preferences: FXCodexPreferences?
	internal let workspaces: [WorkspaceStatus]?
	internal let raycastApplications: [RaycastApplicationStatus]?
	internal let raycastScriptCommands: RaycastScriptCommandStatus?

	internal init(
		status: FXCodexStatus,
		sections: StatusSections
	) {
		self.currentWorkspace = status.currentWorkspace
		self.supportDirectoryURL = status.supportDirectoryURL
		self.applicationURL = status.applicationURL
		self.preferences = sections.preferences ? status.preferences : nil
		self.workspaces = sections.workspaces ? status.workspaces : nil
		self.raycastApplications = sections.integrations ? status.raycastApplications : nil
		self.raycastScriptCommands = sections.integrations ? status.raycastScriptCommands : nil
	}
}

internal struct StatusSections: Equatable {
	internal let preferences: Bool
	internal let workspaces: Bool
	internal let integrations: Bool

	internal init(
		preferences: Bool,
		workspaces: Bool,
		integrations: Bool
	) {
		self.preferences = preferences
		self.workspaces = workspaces
		self.integrations = integrations
	}
}
