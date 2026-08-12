import Foundation
import FXCodexClient

internal enum WorkspacePathComponent: String, CaseIterable, Codable, Equatable, Sendable {
	case workspaceRoot = "workspace-root"
	case codexHome = "codex-home"
	case userData = "user-data"
}

internal struct ResolvedWorkspacePaths: Equatable, Sendable {
	internal let workspace: Workspace
	internal let workspaceRootURL: URL
	internal let codexHomeURL: URL
	internal let userDataURL: URL

	internal init(
		workspace: Workspace
	) throws {
		guard
			let workspaceRootURL = workspace.rootURL,
			let codexHomeURL = workspace.codexHomeURL,
			let userDataURL = workspace.userDataURL
		else {
			throw FXCodexError.invalidStorage(
				"workspace paths are missing for \(workspace.name)"
			)
		}

		self.workspace = workspace
		self.workspaceRootURL = workspaceRootURL
		self.codexHomeURL = codexHomeURL
		self.userDataURL = userDataURL
	}

	internal func url(
		for component: WorkspacePathComponent
	) -> URL {
		switch component {
		case .workspaceRoot: self.workspaceRootURL
		case .codexHome: self.codexHomeURL
		case .userData: self.userDataURL
		}
	}
}

internal struct WorkspacePathSections: Equatable, Sendable {
	internal let workspaceRoot: Bool
	internal let codexHome: Bool
	internal let userData: Bool

	internal init(
		workspaceRoot: Bool,
		codexHome: Bool,
		userData: Bool
	) {
		self.workspaceRoot = workspaceRoot
		self.codexHome = codexHome
		self.userData = userData
	}
}

internal struct WorkspacePathsOutput: Encodable {
	internal let workspaceID: WorkspaceID
	internal let workspaceName: String
	internal let workspaceKind: WorkspaceKind
	internal let workspaceRootURL: URL?
	internal let codexHomeURL: URL?
	internal let userDataURL: URL?

	internal init(
		paths: ResolvedWorkspacePaths,
		sections: WorkspacePathSections
	) {
		self.workspaceID = paths.workspace.id
		self.workspaceName = paths.workspace.name
		self.workspaceKind = paths.workspace.kind
		self.workspaceRootURL = sections.workspaceRoot ? paths.workspaceRootURL : nil
		self.codexHomeURL = sections.codexHome ? paths.codexHomeURL : nil
		self.userDataURL = sections.userData ? paths.userDataURL : nil
	}
}
