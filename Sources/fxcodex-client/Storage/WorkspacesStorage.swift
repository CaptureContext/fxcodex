import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct WorkspacesStorageClient: Sendable {
	public var prepare: @Sendable () throws -> Void
	public var list: @Sendable () throws -> [Workspace]
	public var findWorkspace: @Sendable (_ named: String?) throws -> Workspace
	public var findWorkspaceByID: @Sendable (_ id: WorkspaceID) throws -> Workspace
	public var currentWorkspace: @Sendable () throws -> Workspace
	public var create: @Sendable (String) throws -> Workspace
	public var save: @Sendable (Workspace) throws -> Workspace
	public var delete: @Sendable (Workspace) throws -> Void
	public var erase: @Sendable (Workspace) throws -> Workspace
	public var rename: @Sendable (Workspace, _ to: String) throws -> Workspace
	public var setCurrent: @Sendable (Workspace) throws -> Void
}

extension DependencyValues {
	private enum WorkspacesStorageClientKey: DependencyKey {
		static var liveValue: WorkspacesStorageClient {
			let storage = WorkspacesStorage(fileManager: .default)
			return .init(
				prepare: storage.prepare,
				list: storage.workspaces,
				findWorkspace: storage.workspace(named:),
				findWorkspaceByID: storage.workspace(id:),
				currentWorkspace: storage.currentWorkspace,
				create: storage.createWorkspace,
				save: storage.saveWorkspace,
				delete: { try storage.deleteWorkspace(id: $0.id) },
				erase: { try storage.eraseWorkspace(id: $0.id) },
				rename: { try storage.renameWorkspace(id: $0.id, to: $1) },
				setCurrent: { try storage.useWorkspace(id: $0.id) }
			)
		}
	}

	@_spi(Internals)
	public var _fxcodexWorkspaces: WorkspacesStorageClient {

		get { self[WorkspacesStorageClientKey.self] }
		set { self[WorkspacesStorageClientKey.self] = newValue }
	}
}

public final class WorkspacesStorage: @unchecked Sendable {
	private let decoder = JSONDecoder()
	private let encoder: JSONEncoder
	private let fileManager: FileManager
	private let lock: StorageLock
	private let paths: FXCodexPaths

	public init(fileManager: FileManager) {
		@Dependency(\._fxcodexPaths)
		var paths

		let encoder = FXCodexJSONCoding.encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		self.encoder = encoder
		self.fileManager = fileManager
		self.paths = paths
		self.lock = StorageLock(fileManager: fileManager, paths: paths)
	}

	public func prepare() throws {
		try Migrator(fileManager: self.fileManager, paths: self.paths).migrateIfNeeded()
	}

	public func workspaces() throws -> [Workspace] {
		try self.prepare()
		let configuration = try self.loadConfiguration()
		return try self.workspaceConfigurations()
			.map { self.workspace(from: $0, configuration: configuration) }
			.sorted {
				if $0.kind != $1.kind { return $0.kind == .primary }
				return $0.name < $1.name
			}
	}

	public func workspace(named name: String?) throws -> Workspace {
		try self.prepare()
		let configuration = try self.loadConfiguration()
		if name == nil {
			return try self.workspace(id: configuration.currentWorkspaceID, configuration: configuration)
		}

		guard let metadata = try self.workspaceConfigurations().first(where: { $0.name == name }) else {
			throw FXCodexError.workspaceNotFound(name ?? "")
		}

		return self.workspace(from: metadata, configuration: configuration)
	}

	public func workspace(id: WorkspaceID) throws -> Workspace {
		try self.prepare()
		return try self.workspace(id: id, configuration: self.loadConfiguration())
	}

	public func currentWorkspace() throws -> Workspace {
		try self.workspace(named: nil)
	}

	public func currentWorkspaceName() throws -> String {
		try self.currentWorkspace().name
	}

	public func currentWorkspaceID() throws -> WorkspaceID {
		try self.currentWorkspace().id
	}

	@discardableResult
	public func createWorkspace(named name: String) throws -> Workspace {
		try self.validateWorkspaceName(name)
		guard name != Workspace.primaryName else { throw FXCodexError.primaryWorkspaceMutation }
		try self.prepare()
		guard try self.workspaceConfigurations().allSatisfy({ $0.name != name }) else {
			throw FXCodexError.workspaceAlreadyExists(name)
		}

		let metadata = WorkspaceConfiguration(id: .generate(), name: name, kind: .managed)
		let rootURL = self.workspaceRootURL(for: metadata.id)
		try self.fileManager.createDirectory(
			at: rootURL,
			withIntermediateDirectories: false,
			attributes: [.posixPermissions: 0o700]
		)
		do {
			try self.fileManager.createDirectory(
				at: rootURL.appending(path: "codex-home", directoryHint: .isDirectory),
				withIntermediateDirectories: false,
				attributes: [.posixPermissions: 0o700]
			)
			try self.fileManager.createDirectory(
				at: rootURL.appending(path: "user-data", directoryHint: .isDirectory),
				withIntermediateDirectories: false,
				attributes: [.posixPermissions: 0o700]
			)
			try self.save(metadata: metadata)
		} catch {
			try? self.fileManager.removeItem(at: rootURL)
			throw error
		}
		return self.workspace(from: metadata, configuration: try self.loadConfiguration())
	}

	@discardableResult
	public func saveWorkspace(_ workspace: Workspace) throws -> Workspace {
		let existing = try self.workspace(id: workspace.id)
		guard existing.name == workspace.name, existing.kind == workspace.kind else {
			throw FXCodexError.invalidStorage("workspace identity and metadata cannot be changed through save")
		}

		try self.lock.withLock {
			var configuration = try self.loadConfiguration()
			let integrationIDs = Set(configuration.integrations.keys).union(workspace.integrations.keys)

			for integrationID in integrationIDs {
				var integration = Self.dictionary(configuration.integrations[integrationID]) ?? [:]
				var workspaces = Self.dictionary(integration["workspaces"]) ?? [:]

				if let attributes = workspace.integrations[integrationID] {
					workspaces[workspace.id.rawValue] = attributes
				} else {
					workspaces.removeValue(forKey: workspace.id.rawValue)
				}

				if workspaces.isEmpty {
					integration.removeValue(forKey: "workspaces")
				} else {
					integration["workspaces"] = .dictionary(workspaces)
				}

				if integration.isEmpty {
					configuration.integrations.removeValue(forKey: integrationID)
				} else {
					configuration.integrations[integrationID] = .dictionary(integration)
				}
			}
			try self.save(configuration: configuration)
		}

		return try self.workspace(id: workspace.id)
	}

	public func deleteWorkspace(named name: String?) throws {
		try self.deleteWorkspace(id: self.workspace(named: name).id)
	}

	public func deleteWorkspace(id: WorkspaceID) throws {
		let workspace = try self.workspace(id: id)
		guard workspace.kind == .managed else { throw FXCodexError.primaryWorkspaceMutation }

		guard let rootURL = workspace.rootURL
		else { throw FXCodexError.workspaceNotFound(workspace.name) }

		try self.validateManagedWorkspaceURL(rootURL)
		try self.fileManager.removeItem(at: rootURL)

		try self.lock.withLock {
			var configuration = try self.loadConfiguration()
			configuration.removeWorkspaceAttributes(id: id)
			if configuration.currentWorkspaceID == id {
				configuration.currentWorkspaceID = try self.primaryWorkspaceConfiguration().id
			}
			try self.save(configuration: configuration)
		}
	}

	@discardableResult
	public func eraseWorkspace(named name: String?) throws -> Workspace {
		try self.eraseWorkspace(id: self.workspace(named: name).id)
	}

	@discardableResult
	public func eraseWorkspace(id: WorkspaceID) throws -> Workspace {
		let workspace = try self.workspace(id: id)
		guard workspace.kind == .managed else { throw FXCodexError.primaryWorkspaceMutation }

		guard
			let rootURL = workspace.rootURL,
			let codexHomeURL = workspace.codexHomeURL,
			let userDataURL = workspace.userDataURL
		else { throw FXCodexError.workspaceNotFound(workspace.name) }

		try self.validateManagedWorkspaceURL(rootURL)
		for directoryURL in [codexHomeURL, userDataURL] {
			try self.eraseDirectory(at: directoryURL, inside: rootURL)
		}
		return try self.workspace(id: id)
	}

	@discardableResult
	public func renameWorkspace(from oldName: String, to newName: String) throws -> Workspace {
		try self.renameWorkspace(id: self.workspace(named: oldName).id, to: newName)
	}

	@discardableResult
	public func renameWorkspace(id: WorkspaceID, to newName: String) throws -> Workspace {
		let workspace = try self.workspace(id: id)
		guard workspace.kind == .managed else { throw FXCodexError.primaryWorkspaceMutation }
		try self.validateWorkspaceName(newName)
		guard newName != Workspace.primaryName else { throw FXCodexError.primaryWorkspaceMutation }

		guard try self.workspaceConfigurations().allSatisfy({ $0.id == id || $0.name != newName }) else {
			throw FXCodexError.workspaceAlreadyExists(newName)
		}

		var metadata = try self.loadWorkspaceConfiguration(id: id)
		metadata.name = newName
		try self.save(metadata: metadata)
		return try self.workspace(id: id)
	}

	public func useWorkspace(named name: String) throws {
		try self.useWorkspace(id: self.workspace(named: name).id)
	}

	public func useWorkspace(id: WorkspaceID) throws {
		_ = try self.workspace(id: id)
		try self.lock.withLock {
			var configuration = try self.loadConfiguration()
			configuration.currentWorkspaceID = id
			try self.save(configuration: configuration)
		}
	}
}

private extension WorkspacesStorage {
	func loadConfiguration() throws -> StorageConfiguration {
		try self.decoder.decode(StorageConfiguration.self, from: Data(contentsOf: self.paths.configurationURL))
	}

	func save(configuration: StorageConfiguration) throws {
		try self.encoder.encode(configuration).write(to: self.paths.configurationURL, options: [.atomic])
	}

	func loadWorkspaceConfiguration(id: WorkspaceID) throws -> WorkspaceConfiguration {
		try self.decoder.decode(
			WorkspaceConfiguration.self,
			from: Data(contentsOf: self.workspaceMetadataURL(for: id))
		)
	}

	func save(metadata: WorkspaceConfiguration) throws {
		try self.encoder.encode(metadata).write(to: self.workspaceMetadataURL(for: metadata.id), options: [.atomic])
	}

	func workspaceConfigurations() throws -> [WorkspaceConfiguration] {
		try self.fileManager.contentsOfDirectory(
			at: self.paths.workspacesURL,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)
		.filter { directory in
			(try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
				&& WorkspaceID(directory.lastPathComponent) != nil
		}
		.map { directory in
			guard let id = WorkspaceID(directory.lastPathComponent) else { preconditionFailure() }
			let metadata = try self.loadWorkspaceConfiguration(id: id)
			guard metadata.schemaVersion == .v2_0, metadata.id == id else {
				throw FXCodexError.invalidStorage("workspace directory and metadata do not match")
			}
			return metadata
		}
	}

	func primaryWorkspaceConfiguration() throws -> WorkspaceConfiguration {
		guard let primary = try self.workspaceConfigurations().first(where: { $0.kind == .primary })
		else {
			throw FXCodexError.invalidStorage("primary workspace metadata is missing")
		}

		return primary
	}

	func workspace(id: WorkspaceID, configuration: StorageConfiguration) throws -> Workspace {
		guard let metadata = try self.workspaceConfigurations().first(where: { $0.id == id }) else {
			throw FXCodexError.workspaceNotFound(id.rawValue)
		}

		return self.workspace(from: metadata, configuration: configuration)
	}

	func workspace(from metadata: WorkspaceConfiguration, configuration: StorageConfiguration) -> Workspace {
		let rootURL = self.workspaceRootURL(for: metadata.id)
		let integrations = configuration.workspaceAttributes(id: metadata.id)
		if metadata.kind == .primary {
			return .init(
				id: metadata.id,
				name: metadata.name,
				kind: metadata.kind,
				rootURL: nil,
				codexHomeURL: nil,
				userDataURL: nil,
				integrations: integrations
			)
		}
		return .init(
			id: metadata.id,
			name: metadata.name,
			kind: metadata.kind,
			rootURL: rootURL,
			codexHomeURL: rootURL.appending(path: "codex-home", directoryHint: .isDirectory),
			userDataURL: rootURL.appending(path: "user-data", directoryHint: .isDirectory),
			integrations: integrations
		)
	}

	func workspaceRootURL(for id: WorkspaceID) -> URL {
		self.paths.workspacesURL.appending(path: id.rawValue, directoryHint: .isDirectory).standardizedFileURL
	}

	func workspaceMetadataURL(for id: WorkspaceID) -> URL {
		self.workspaceRootURL(for: id).appending(path: "workspace.json", directoryHint: .notDirectory)
	}

	func validateWorkspaceName(_ name: String) throws {
		let pattern: Regex<Substring> = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/
		guard name.wholeMatch(of: pattern) != nil else { throw FXCodexError.invalidWorkspaceName(name) }
	}

	func validateManagedWorkspaceURL(_ url: URL) throws {
		let parentURL = url.deletingLastPathComponent().standardizedFileURL
		guard parentURL == self.paths.workspacesURL.standardizedFileURL else {
			throw CocoaError(.fileWriteNoPermission)
		}
	}

	func eraseDirectory(at directoryURL: URL, inside rootURL: URL) throws {
		let directoryURL = directoryURL.standardizedFileURL
		guard directoryURL.deletingLastPathComponent() == rootURL.standardizedFileURL else {
			throw CocoaError(.fileWriteNoPermission)
		}

		if self.fileManager.fileExists(atPath: directoryURL.path) {
			let values = try directoryURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
			if values.isDirectory != true || values.isSymbolicLink == true {
				try self.fileManager.removeItem(at: directoryURL)
				try self.fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)

			} else {
				for itemURL in try self.fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) {
					try self.fileManager.removeItem(at: itemURL)
				}
			}

		} else {
			try self.fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: false)
		}

		try self.fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
	}

	static func dictionary(_ value: CodableValue?) -> [String: CodableValue]? {
		guard case let .dictionary(dictionary) = value else { return nil }
		return dictionary
	}
}

private extension StorageConfiguration {
	func workspaceAttributes(id: WorkspaceID) -> [String: CodableValue] {
		self.integrations.reduce(into: [:]) { result, item in

			guard
				case let .dictionary(integration) = item.value,
				case let .dictionary(workspaces) = integration["workspaces"],
				let attributes = workspaces[id.rawValue]
			else { return }

			result[item.key] = attributes
		}
	}

	mutating func removeWorkspaceAttributes(id: WorkspaceID) {
		for integrationID in self.integrations.keys.sorted() {
			guard case var .dictionary(integration) = self.integrations[integrationID] else { continue }
			if case var .dictionary(workspaces) = integration["workspaces"] {
				workspaces.removeValue(forKey: id.rawValue)

				if workspaces.isEmpty {
					integration.removeValue(forKey: "workspaces")
				} else {
					integration["workspaces"] = .dictionary(workspaces)
				}
			}

			if integration.isEmpty {
				self.integrations.removeValue(forKey: integrationID)
			} else {
				self.integrations[integrationID] = .dictionary(integration)
			}
		}
	}
}
