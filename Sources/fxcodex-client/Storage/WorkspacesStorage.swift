import Foundation
import FXCodexFS
import Dependencies
import DependenciesMacros

@DependencyClient
public struct WorkspacesStorageClient: Sendable {
	public var prepare: @Sendable () throws -> Void
	public var list: @Sendable () throws -> [Workspace]
	public var findWorkspace: @Sendable (_ named: String?) throws -> Workspace
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
				currentWorkspace: { try storage.workspace(named: storage.currentWorkspaceName()) },
				create: storage.createWorkspace,
				save: storage.saveWorkspace,
				delete: { try storage.deleteWorkspace(named: $0.name) },
				erase: { try storage.eraseWorkspace(named: $0.name) },
				rename: { try storage.renameWorkspace(from: $0.name, to: $1) },
				setCurrent: { try storage.useWorkspace(named: $0.name) }
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
	private let decoder: JSONDecoder
	private let encoder: JSONEncoder
	private let fileManager: FileManager

	@Dependency(\._fxcodexPaths)
	private var paths: FXCodexPaths

	public init(fileManager: FileManager) {
		let encoder: JSONEncoder = FXCodexJSONCoding.encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		self.decoder = .init()
		self.encoder = encoder
		self.fileManager = fileManager
	}

	public func prepare() throws {
		try Folder(
			path: self.paths.rootURL.path,
			create: true
		)
		.createSubfolderIfNeeded(withName: self.paths.workspacesURL.lastPathComponent)

		if !self.fileManager.fileExists(atPath: self.paths.configurationURL.path) {
			try self.save(configuration: .init(
				currentWorkspaceName: Workspace.primaryName,
				workspaceIntegrations: [:]
			))
		}
	}

	public func workspaces() throws -> [Workspace] {
		try self.prepare()

		let names: [String] = try self.fileManager.contentsOfDirectory(
			at: self.paths.workspacesURL,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)
		.filter { url in
			(try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
		}
		.map(\.lastPathComponent)
		.sorted()

		let configuration: Configuration = try self.loadConfiguration()
		let primaryWorkspace: Workspace = self.primaryWorkspace(
			integrations: configuration.workspaceIntegrations[Workspace.primaryName] ?? [:]
		)
		let managedWorkspaces: [Workspace] = names.map { name in
			self.managedWorkspace(
				named: name,
				integrations: configuration.workspaceIntegrations[name] ?? [:]
			)
		}
		return [primaryWorkspace] + managedWorkspaces
	}

	public func workspace(named name: String?) throws -> Workspace {
		try self.prepare()
		let configuration: Configuration = try self.loadConfiguration()
		let resolvedName: String = name ?? self.currentWorkspaceName(
			configuration: configuration
		)
		let integrations: [String: CodableValue] = configuration.workspaceIntegrations[resolvedName] ?? [:]

		if resolvedName == Workspace.primaryName {
			return self.primaryWorkspace(integrations: integrations)
		}

		let workspace: Workspace = self.managedWorkspace(
			named: resolvedName,
			integrations: integrations
		)
		guard let rootURL = workspace.rootURL else {
			throw FXCodexError.workspaceNotFound(resolvedName)
		}
		guard self.fileManager.fileExists(atPath: rootURL.path)
		else { throw FXCodexError.workspaceNotFound(resolvedName) }

		return workspace
	}

	public func currentWorkspaceName() throws -> String {
		try self.prepare()
		let configuration: Configuration = try self.loadConfiguration()
		return self.currentWorkspaceName(configuration: configuration)
	}

	@discardableResult
	public func createWorkspace(named name: String) throws -> Workspace {
		try self.validateWorkspaceName(name)
		guard name != Workspace.primaryName
		else { throw FXCodexError.primaryWorkspaceMutation }

		try self.prepare()
		let workspace: Workspace = self.managedWorkspace(
			named: name,
			integrations: [:]
		)
		guard let rootURL = workspace.rootURL else {
			throw FXCodexError.workspaceNotFound(name)
		}
		guard !self.fileManager.fileExists(atPath: rootURL.path)
		else { throw FXCodexError.workspaceAlreadyExists(name) }

		let rootFolder: Folder = try .init(
			path: rootURL.path,
			create: true
		)
		try rootFolder.createSubfolder(named: "codex-home")
		try rootFolder.createSubfolder(named: "user-data")
		try self.fileManager.setAttributes(
			[.posixPermissions: 0o700],
			ofItemAtPath: rootURL.path
		)

		return workspace
	}

	@discardableResult
	public func saveWorkspace(_ workspace: Workspace) throws -> Workspace {
		_ = try self.workspace(named: workspace.name)
		var configuration: Configuration = try self.loadConfiguration()

		if workspace.integrations.isEmpty {
			configuration.workspaceIntegrations.removeValue(forKey: workspace.name)
		} else {
			configuration.workspaceIntegrations[workspace.name] = workspace.integrations
		}

		try self.save(configuration: configuration)
		return workspace
	}

	public func deleteWorkspace(named name: String?) throws {
		let workspace: Workspace = try self.workspace(named: name)
		guard workspace.kind == .managed
		else { throw FXCodexError.primaryWorkspaceMutation }
		let wasCurrent: Bool = try self.currentWorkspaceName() == workspace.name
		guard let rootURL = workspace.rootURL else {
			throw FXCodexError.workspaceNotFound(workspace.name)
		}

		try self.validateManagedWorkspaceURL(rootURL)
		try Folder(path: rootURL.path).delete()

		var configuration: Configuration = try self.loadConfiguration()
		configuration.workspaceIntegrations.removeValue(forKey: workspace.name)
		if wasCurrent {
			configuration.currentWorkspaceName = Workspace.primaryName
		}
		try self.save(configuration: configuration)
	}

	@discardableResult
	public func eraseWorkspace(named name: String?) throws -> Workspace {
		let workspace: Workspace = try self.workspace(named: name)
		guard workspace.kind == .managed
		else { throw FXCodexError.primaryWorkspaceMutation }
		guard
			let rootURL = workspace.rootURL,
			let codexHomeURL = workspace.codexHomeURL,
			let userDataURL = workspace.userDataURL
		else { throw FXCodexError.workspaceNotFound(workspace.name) }

		try self.validateManagedWorkspaceURL(rootURL)
		for directoryURL in [codexHomeURL, userDataURL] {
			try self.eraseDirectory(
				at: directoryURL,
				inside: rootURL
			)
		}

		var erasedWorkspace: Workspace = workspace
		erasedWorkspace.integrations = [:]
		return try self.saveWorkspace(erasedWorkspace)
	}

	@discardableResult
	public func renameWorkspace(
		from oldName: String,
		to newName: String
	) throws -> Workspace {
		let workspace: Workspace = try self.workspace(named: oldName)
		guard workspace.kind == .managed
		else { throw FXCodexError.primaryWorkspaceMutation }

		try self.validateWorkspaceName(newName)
		guard newName != Workspace.primaryName
		else { throw FXCodexError.primaryWorkspaceMutation }

		let destinationURL: URL = self.workspaceRootURL(forName: newName)
		guard !self.fileManager.fileExists(atPath: destinationURL.path)
		else { throw FXCodexError.workspaceAlreadyExists(newName) }
		guard let rootURL = workspace.rootURL else {
			throw FXCodexError.workspaceNotFound(workspace.name)
		}
		let wasCurrent: Bool = try self.currentWorkspaceName() == workspace.name

		try self.validateManagedWorkspaceURL(rootURL)
		try self.fileManager.moveItem(
			at: rootURL,
			to: destinationURL
		)

		var configuration: Configuration = try self.loadConfiguration()
		let integrations: [String: CodableValue] = configuration.workspaceIntegrations
		.removeValue(forKey: workspace.name)
		?? workspace.integrations
		if integrations.isEmpty {
			configuration.workspaceIntegrations.removeValue(forKey: newName)
		} else {
			configuration.workspaceIntegrations[newName] = integrations
		}
		if wasCurrent {
			configuration.currentWorkspaceName = newName
		}
		try self.save(configuration: configuration)

		return self.managedWorkspace(
			named: newName,
			integrations: integrations
		)
	}

	public func useWorkspace(named name: String) throws {
		let workspace: Workspace = try self.workspace(named: name)
		var configuration: Configuration = try self.loadConfiguration()
		configuration.currentWorkspaceName = workspace.name
		try self.save(configuration: configuration)
	}

}

extension WorkspacesStorage {
	private struct Configuration: Codable {
		var currentWorkspaceName: String
		var workspaceIntegrations: [String: [String: CodableValue]]

		init(
			currentWorkspaceName: String,
			workspaceIntegrations: [String: [String: CodableValue]]
		) {
			self.currentWorkspaceName = currentWorkspaceName
			self.workspaceIntegrations = workspaceIntegrations
		}

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			self.currentWorkspaceName = try container.decode(
				String.self,
				forKey: .currentWorkspaceName
			)
			self.workspaceIntegrations = try container.decodeIfPresent(
				[String: [String: CodableValue]].self,
				forKey: .workspaceIntegrations
			)
			?? [:]
		}

		private enum CodingKeys: String, CodingKey {
			case currentWorkspaceName = "current_workspace_name"
			case workspaceIntegrations = "workspace_integrations"
		}
	}

	private func loadConfiguration() throws -> Configuration {
		let data: Data = try .init(contentsOf: self.paths.configurationURL)
		return try self.decoder.decode(
			Configuration.self,
			from: data
		)
	}

	private func save(configuration: Configuration) throws {
		let data: Data = try self.encoder.encode(configuration)
		try data.write(
			to: self.paths.configurationURL,
			options: [.atomic]
		)
	}

	private func primaryWorkspace(
		integrations: [String: CodableValue]
	) -> Workspace {
		.init(
			name: Workspace.primaryName,
			kind: .primary,
			rootURL: nil,
			codexHomeURL: nil,
			userDataURL: nil,
			integrations: integrations
		)
	}

	private func managedWorkspace(
		named name: String,
		integrations: [String: CodableValue]
	) -> Workspace {
		let rootURL: URL = self.workspaceRootURL(forName: name)
		return .init(
			name: name,
			kind: .managed,
			rootURL: rootURL,
			codexHomeURL: rootURL.appending(
				path: "codex-home",
				directoryHint: .isDirectory
			),
			userDataURL: rootURL.appending(
				path: "user-data",
				directoryHint: .isDirectory
			),
			integrations: integrations
		)
	}

	private func currentWorkspaceName(
		configuration: Configuration
	) -> String {
		if configuration.currentWorkspaceName == Workspace.primaryName {
			return Workspace.primaryName
		}

		let workspaceURL: URL = self.workspaceRootURL(
			forName: configuration.currentWorkspaceName
		)
		return self.fileManager.fileExists(atPath: workspaceURL.path)
		? configuration.currentWorkspaceName
		: Workspace.primaryName
	}

	private func workspaceRootURL(forName name: String) -> URL {
		self.paths.workspacesURL.appending(
			path: name,
			directoryHint: .isDirectory
		).standardizedFileURL
	}

	private func validateWorkspaceName(_ name: String) throws {
		let pattern: Regex<Substring> = /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/
		guard name.wholeMatch(of: pattern) != nil
		else { throw FXCodexError.invalidWorkspaceName(name) }
	}

	private func validateManagedWorkspaceURL(_ url: URL) throws {
		let parentURL: URL = url.deletingLastPathComponent().standardizedFileURL
		guard parentURL == self.paths.workspacesURL.standardizedFileURL
		else { throw CocoaError(.fileWriteNoPermission) }
	}

	private func eraseDirectory(
		at directoryURL: URL,
		inside rootURL: URL
	) throws {
		let standardizedDirectoryURL: URL = directoryURL.standardizedFileURL
		guard standardizedDirectoryURL.deletingLastPathComponent() == rootURL.standardizedFileURL
		else { throw CocoaError(.fileWriteNoPermission) }

		if self.fileManager.fileExists(atPath: standardizedDirectoryURL.path) {
			let values: URLResourceValues = try standardizedDirectoryURL.resourceValues(
				forKeys: [
					.isDirectoryKey,
					.isSymbolicLinkKey,
				]
			)
			if values.isDirectory != true || values.isSymbolicLink == true {
				try self.fileManager.removeItem(at: standardizedDirectoryURL)
				try self.fileManager.createDirectory(
					at: standardizedDirectoryURL,
					withIntermediateDirectories: false,
					attributes: nil
				)
			} else {
				for itemURL in try self.fileManager.contentsOfDirectory(
					at: standardizedDirectoryURL,
					includingPropertiesForKeys: nil,
					options: []
				) {
					try self.fileManager.removeItem(at: itemURL)
				}
			}
		} else {
			try self.fileManager.createDirectory(
				at: standardizedDirectoryURL,
				withIntermediateDirectories: false,
				attributes: nil
			)
		}

		try self.fileManager.setAttributes(
			[.posixPermissions: 0o700],
			ofItemAtPath: standardizedDirectoryURL.path
		)
	}
}
