import Foundation
import Dependencies
import DependenciesMacros

extension Integrations {
	@DependencyClient
	public struct Raycast: Sendable {
		public var applicationStatus: @Sendable (RaycastEdition) async throws -> RaycastApplicationStatus
		public var applicationInstallation: @Sendable (RaycastEdition) async throws -> RaycastApplicationInstallation
		public var installScriptCommands: @Sendable (URL, URL, Bool, Bool) async throws -> RaycastScriptCommandStatus
		public var syncScriptCommands: @Sendable (URL) async throws -> RaycastScriptCommandStatus
		public var uninstallScriptCommands: @Sendable () async throws -> RaycastScriptCommandStatus
		public var scriptCommandStatus: @Sendable () async throws -> RaycastScriptCommandStatus
		public var workspaceCreated: @Sendable (Workspace) async throws -> Workspace
		public var workspaceDeleted: @Sendable (Workspace) async throws -> Void
		public var workspaceErased: @Sendable (Workspace) async throws -> Void
		public var workspaceRenamed: @Sendable (Workspace, Workspace) async throws -> Workspace
	}
}

extension DependencyValues {
	private enum RaycastIntegrationKey: DependencyKey {
		static var liveValue: Integrations.Raycast {
			let integration = RaycastIntegration()
			return .init(
				applicationStatus: {
					await integration.applicationStatus(for: $0)
				},
				applicationInstallation: {
					try await integration.applicationInstallation(for: $0)
				},
				installScriptCommands: {
					try await integration.installScriptCommands(
						at: $0,
						fxcodexExecutableURL: $1,
						includeCurrentWorkspace: $2,
						includeAllWorkspaces: $3
					)
				},
				syncScriptCommands: {
					try await integration.syncScriptCommands(fxcodexExecutableURL: $0)
				},
				uninstallScriptCommands: {
					try await integration.uninstallScriptCommands()
				},
				scriptCommandStatus: {
					try await integration.scriptCommandStatus()
				},
				workspaceCreated: {
					try await integration.workspaceCreated($0)
				},
				workspaceDeleted: {
					try await integration.workspaceDeleted($0)
				},
				workspaceErased: {
					try await integration.workspaceErased($0)
				},
				workspaceRenamed: {
					try await integration.workspaceRenamed(
						from: $0,
						to: $1
					)
				}
			)
		}
	}

	@_spi(Internals)
	public var _fxcodexRaycast: Integrations.Raycast {
		get { self[RaycastIntegrationKey.self] }
		set { self[RaycastIntegrationKey.self] = newValue }
	}
}
