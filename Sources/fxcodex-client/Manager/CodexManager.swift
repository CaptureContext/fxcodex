import Foundation
import Dependencies

actor CodexManager {
	@Dependency(\._fxcodexApplication)
	private var application

	@Dependency(\._fxcodexIntegrations)
	private nonisolated var integrations

	@Dependency(\._fxcodexPaths)
	private var paths: FXCodexPaths

	@Dependency(\._fxcodexPreferences)
	private var preferencesStorage: PreferencesStorageClient

	@Dependency(\._fxcodexSupport)
	private var supportStorage: SupportStorageClient

	@Dependency(\._fxcodexUpdateChecks)
	private var updateChecks: UpdateCheckStorageClient

	@Dependency(\._fxcodexUpdater)
	private var updater: UpdateClient

	@Dependency(\._fxcodexWorkspaces)
	private var workspacesStorage: WorkspacesStorageClient

	init() {}

	func applyAutomaticPreferences(
		currentVersion: SemanticVersion,
		executableURL: URL,
		allowsAutomaticUpdate: Bool
	) async throws -> [FXCodexWarning] {
		let preferences: FXCodexPreferences = try self.preferencesStorage.load()
		var warnings: [FXCodexWarning] = []

		if preferences.autoRename {
			do {
				let result: CodexApplicationRenameResult = try await self.renameApplication(
					to: .codex
				)
				if result.outcome == .conflict {
					warnings.append(self.applicationNameConflictWarning(result))
				}
			} catch {
				if let applicationURL = await self.application.applicationURL(),
					applicationURL.lastPathComponent == CodexApplicationName.codex.rawValue {
					warnings.append(.init(
						code: "automatic_rename_failed",
						message: "Automatic rename failed, but Codex.app is available and will be used: \(error.localizedDescription)"
					))

				} else {
					throw error
				}
			}
		}

		if allowsAutomaticUpdate,
			let channel = preferences.autoUpdate.updateChannel {
			do {
				if try self.updateChecks.claimAutomaticCheck(Date(), 86_400) {
					_ = try await self.updater.update(
						currentVersion,
						channel,
						preferences.autoUpdate.minimumVersion,
						executableURL
					)
				}
			} catch {
				warnings.append(.init(
					code: "automatic_update_failed",
					message: "Automatic update failed: \(error.localizedDescription)"
				))
			}
		}

		return warnings
	}

	func preferences() throws -> FXCodexPreferences {
		try self.preferencesStorage.load()
	}

	func setAutoRename(
		to value: Bool
	) throws -> FXCodexPreferences {
		try self.preferencesStorage.setAutoRename(value)
	}

	func setAutoUpdate(
		to value: AutoUpdatePolicy
	) throws -> FXCodexPreferences {
		try self.preferencesStorage.setAutoUpdate(value)
	}

	func update(
		currentVersion: SemanticVersion,
		channel: UpdateChannel,
		executableURL: URL
	) async throws -> UpdateResult {
		try await self.updater.update(
			currentVersion,
			channel,
			nil,
			executableURL
		)
	}

	func uninstallData(
		_ disposition: UninstallDataDisposition
	) async throws {
		let managedWorkspaces: [Workspace] = try self.workspacesStorage.list().filter {
			$0.kind == .managed
		}

		switch disposition {
		case .leave:
			_ = try await self.integrations.raycast.uninstallScriptCommands()

		case .erase:
			_ = try await self.eraseWorkspaces(managedWorkspaces)
			_ = try await self.integrations.raycast.uninstallScriptCommands()

		case .delete:
			try await self.deleteWorkspaces(managedWorkspaces)
			_ = try await self.integrations.raycast.uninstallScriptCommands()
			try self.supportStorage.removeAll()
		}
	}

	func renameApplication(
		to name: CodexApplicationName
	) async throws -> CodexApplicationRenameResult {
		try await self.application.rename(name)
	}

	func workspaces() throws -> [Workspace] {
		try workspacesStorage.list()
	}

	func prepareStorage() throws {
		try self.workspacesStorage.prepare()
	}

	func storageMigrationPlan() throws -> StorageMigrationPlan? {
		try Migrator(fileManager: .default).migrationPlan()
	}

	func migrateStorage(_ migration: StorageMigration) throws {
		try Migrator(fileManager: .default).migrate(migration)
	}

	func currentWorkspace() throws -> Workspace {
		try workspacesStorage.currentWorkspace()
	}

	func createWorkspace(named name: String) async throws -> Workspace {
		let workspace: Workspace = try self.workspacesStorage.create(name)
		return try await self.integrations.raycast.workspaceCreated(workspace)
	}

	func deleteWorkspace(named name: String?) async throws {
		let workspace: Workspace = try self.workspacesStorage.findWorkspace(named: name)
		try await self.deleteWorkspaces([workspace])
	}

	func deleteWorkspaces(named names: [String]) async throws {
		try await self.deleteWorkspaces(
			try self.managedWorkspaces(named: names)
		)
	}

	func eraseWorkspace(named name: String?) async throws -> Workspace {
		let workspace: Workspace = try self.workspacesStorage.findWorkspace(named: name)
		return try await self.eraseWorkspaces([workspace])[0]
	}

	func eraseWorkspaces(named names: [String]) async throws -> [Workspace] {
		try await self.eraseWorkspaces(
			try self.managedWorkspaces(named: names)
		)
	}

	func renameWorkspace(
		from oldName: String?,
		to newName: String
	) async throws -> Workspace {
		let workspace: Workspace = try self.workspacesStorage.findWorkspace(named: oldName)

		guard try await self.application.runningProcessID(workspace) == nil
		else { throw FXCodexError.workspaceIsRunning(workspace.name) }

		let renamedWorkspace: Workspace = try self.workspacesStorage.rename(
			workspace,
			to: newName
		)
		return try await self.integrations.raycast.workspaceRenamed(
			workspace,
			renamedWorkspace
		)
	}

	func useWorkspace(named name: String) throws {
		try self.workspacesStorage.setCurrent(self.workspacesStorage.findWorkspace(named: name))
	}

	func useWorkspace(id: WorkspaceID) throws {
		try self.workspacesStorage.setCurrent(self.workspacesStorage.findWorkspaceByID(id))
	}

	func openWorkspace(named name: String?) async throws -> Int32 {
		let workspace: Workspace = try self.workspacesStorage.findWorkspace(named: name)
		return try await self.application.open(workspace)
	}

	func openWorkspace(id: WorkspaceID) async throws -> Int32 {
		try await self.application.open(self.workspacesStorage.findWorkspaceByID(id))
	}

	func codexInvocation(
		workspaceName: String?,
		arguments: [String]
	) throws -> CommandInvocation {
		let workspace: Workspace = try self.workspacesStorage.findWorkspace(named: workspaceName)
		let environment: [String: String]

		if workspace.kind == .managed {
			guard let codexHomeURL = workspace.codexHomeURL
			else { throw FXCodexError.workspaceNotFound(workspace.name) }

			environment = ["CODEX_HOME": codexHomeURL.path]

		} else {
			environment = [:]
		}

		return .init(
			executable: "codex",
			arguments: arguments,
			environment: environment
		)
	}

	func status() async throws -> FXCodexStatus {
		let currentWorkspace = try self.workspacesStorage.currentWorkspace()
		var workspaceStatuses: [WorkspaceStatus] = []

		for workspace in try self.workspacesStorage.list() {
			workspaceStatuses.append(.init(
				workspace: workspace,
				isCurrent: workspace.id == currentWorkspace.id,
				processID: try await self.application.runningProcessID(workspace)
			))
		}

		var raycastApplications: [RaycastApplicationStatus] = []

		for edition in RaycastEdition.allCases {
			raycastApplications.append(
				try await self.integrations.raycast.applicationStatus(edition)
			)
		}

		return .init(
			currentWorkspace: currentWorkspace.name,
			currentWorkspaceID: currentWorkspace.id,
			supportDirectoryURL: self.paths.rootURL,
			applicationURL: await self.application.applicationURL(),
			preferences: try self.preferencesStorage.load(),
			workspaces: workspaceStatuses,
			raycastApplications: raycastApplications,
			raycastScriptCommands: try await self.integrations.raycast.scriptCommandStatus()
		)
	}
}

extension CodexManager {
	private func applicationNameConflictWarning(
		_ result: CodexApplicationRenameResult
	) -> FXCodexWarning {
		.init(
			code: "application_name_conflict",
			message: "Both ChatGPT.app and Codex.app are present. \(result.requestedName.rawValue) will be used."
		)
	}

	private func managedWorkspaces(named names: [String]) throws -> [Workspace] {
		var resolvedNames: Set<String> = []

		return try names.compactMap { name in
			guard resolvedNames.insert(name).inserted else { return nil }

			let workspace: Workspace = try self.workspacesStorage.findWorkspace(named: name)

			guard workspace.kind == .managed else { throw FXCodexError.primaryWorkspaceMutation }

			return workspace
		}
	}

	private func ensureStopped(_ workspaces: [Workspace]) async throws {
		for workspace in workspaces {
			guard try await self.application.runningProcessID(workspace) == nil
			else { throw FXCodexError.workspaceIsRunning(workspace.name) }
		}
	}

	private func deleteWorkspaces(_ workspaces: [Workspace]) async throws {
		try await self.ensureStopped(workspaces)

		for workspace in workspaces {
			guard workspace.kind == .managed else { throw FXCodexError.primaryWorkspaceMutation }

			try await self.integrations.raycast.workspaceDeleted(workspace)
			try self.workspacesStorage.delete(workspace)
			try await self.application.removeRecord(workspace)
		}
	}

	private func eraseWorkspaces(_ workspaces: [Workspace]) async throws -> [Workspace] {
		try await self.ensureStopped(workspaces)

		var erasedWorkspaces: [Workspace] = []

		for workspace in workspaces {
			guard workspace.kind == .managed else { throw FXCodexError.primaryWorkspaceMutation }

			try await self.integrations.raycast.workspaceErased(workspace)
			erasedWorkspaces.append(try self.workspacesStorage.erase(workspace))
			try await self.application.removeRecord(workspace)
		}

		return erasedWorkspaces
	}
}
