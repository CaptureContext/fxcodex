import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct FXCodexClient: Sendable {
	public var applyAutomaticPreferences: @Sendable (SemanticVersion, URL, Bool) async throws -> [FXCodexWarning]
	public var preferences: @Sendable () async throws -> FXCodexPreferences
	public var setAutoRename: @Sendable (Bool) async throws -> FXCodexPreferences
	public var setAutoUpdate: @Sendable (AutoUpdatePolicy) async throws -> FXCodexPreferences
	public var update: @Sendable (SemanticVersion, UpdateChannel, URL) async throws -> UpdateResult
	public var uninstallData: @Sendable (UninstallDataDisposition) async throws -> Void
	public var renameApplication: @Sendable (CodexApplicationName) async throws -> CodexApplicationRenameResult
	public var workspaces: @Sendable () async throws -> [Workspace]
	public var currentWorkspace: @Sendable () async throws -> Workspace
	public var createWorkspace: @Sendable (String) async throws -> Workspace
	public var deleteWorkspace: @Sendable (String?) async throws -> Void
	public var deleteWorkspaces: @Sendable ([String]) async throws -> Void
	public var eraseWorkspace: @Sendable (String?) async throws -> Workspace
	public var eraseWorkspaces: @Sendable ([String]) async throws -> [Workspace]
	public var renameWorkspace: @Sendable (String?, String) async throws -> Workspace
	public var useWorkspace: @Sendable (String) async throws -> Void
	public var openWorkspace: @Sendable (String?) async throws -> Int32
	public var codexInvocation: @Sendable (String?, [String]) async throws -> CommandInvocation
	public var status: @Sendable () async throws -> FXCodexStatus
}

extension FXCodexClient {
	public var integrations: Integrations {
		Dependency(\._fxcodexIntegrations).wrappedValue
	}
}

extension DependencyValues {
	private enum FXCodexClientKey: DependencyKey {
		static var liveValue: FXCodexClient {
			let manager = CodexManager()
			return .init(
				applyAutomaticPreferences: manager.applyAutomaticPreferences,
				preferences: { try await manager.preferences() },
				setAutoRename: { try await manager.setAutoRename(to: $0) },
				setAutoUpdate: { try await manager.setAutoUpdate(to: $0) },
				update: { try await manager.update(currentVersion: $0, channel: $1, executableURL: $2) },
				uninstallData: manager.uninstallData,
				renameApplication: manager.renameApplication,
				workspaces: { try await manager.workspaces() },
				currentWorkspace: { try await manager.currentWorkspace() },
				createWorkspace: { try await manager.createWorkspace(named: $0) },
				deleteWorkspace: manager.deleteWorkspace,
				deleteWorkspaces: manager.deleteWorkspaces,
				eraseWorkspace: manager.eraseWorkspace,
				eraseWorkspaces: manager.eraseWorkspaces,
				renameWorkspace: manager.renameWorkspace,
				useWorkspace: { try await manager.useWorkspace(named: $0) },
				openWorkspace: manager.openWorkspace,
				codexInvocation: { try await manager.codexInvocation(workspaceName: $0, arguments: $1) },
				status: manager.status
			)
		}
	}

	public var fxCodexClient: FXCodexClient {
		get { self[FXCodexClientKey.self] }
		set { self[FXCodexClientKey.self] = newValue }
	}
}
