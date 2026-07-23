import Darwin
import Dependencies
import Foundation

final class Migrator: @unchecked Sendable {
	private enum MigrationV1 {
		static let migration = StorageMigration(
			sourceVersion: .v1_0,
			destinationVersion: .v2_0,
			steps: [
				"Assign stable IDs to existing workspaces",
				"Move managed workspaces into ID-based directories",
				"Convert runtime records and integration attributes",
				"Write and validate schema 2.0 configuration",
			],
			requiresUserInput: false
		)
	}

	private struct LegacyConfiguration: Codable {
		var currentWorkspaceName: String
		var workspaceIntegrations: [String: [String: CodableValue]]

		init(from decoder: any Decoder) throws {
			let container = try decoder.container(keyedBy: CodingKeys.self)
			self.currentWorkspaceName = try container.decode(String.self, forKey: .currentWorkspaceName)
			self.workspaceIntegrations = try container.decodeIfPresent(
				[String: [String: CodableValue]].self,
				forKey: .workspaceIntegrations
			) ?? [:]
		}

		private enum CodingKeys: String, CodingKey {
			case currentWorkspaceName = "current_workspace_name"
			case workspaceIntegrations = "workspace_integrations"
		}
	}

	private struct ScriptCommandConfiguration: Equatable {
		let path: String
		let executablePath: String
	}

	private let decoder: JSONDecoder
	private let encoder: JSONEncoder
	private let fileManager: FileManager
	private let lock: StorageLock
	private let paths: FXCodexPaths

	init(fileManager: FileManager) {
		@Dependency(\._fxcodexPaths)
		var paths

		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let encoder = FXCodexJSONCoding.encoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		self.encoder = encoder
		self.decoder = decoder
		self.fileManager = fileManager
		self.paths = paths
		self.lock = StorageLock(fileManager: fileManager, paths: paths)
	}

	init(fileManager: FileManager, paths: FXCodexPaths) {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let encoder = FXCodexJSONCoding.encoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		self.encoder = encoder
		self.decoder = decoder
		self.fileManager = fileManager
		self.paths = paths
		self.lock = StorageLock(fileManager: fileManager, paths: paths)
	}

	func migrateIfNeeded() throws {
		try self.lock.withLock {
			try self.fileManager.createDirectory(
				at: self.paths.workspacesURL,
				withIntermediateDirectories: true,
				attributes: [.posixPermissions: 0o700]
			)

			guard self.fileManager.fileExists(atPath: self.paths.configurationURL.path) else {
				try self.bootstrap()
				return
			}

			let version = try self.detectVersion()

			if version == .v2_0 {
				try self.verifyV2()
				try? self.fileManager.removeItem(at: self.paths.migrationURL)
				return
			}

			try self.validateSource(version: version)

			for migration in try self.migrationSequence(from: version) {
				try self.perform(migration)
			}
			try self.verifyV2()
		}
	}

	func migrate(_ migration: StorageMigration) throws {
		try self.lock.withLock {
			guard self.fileManager.fileExists(atPath: self.paths.configurationURL.path) else {
				throw FXCodexError.invalidStorage("configuration is missing")
			}

			let sourceVersion = try self.detectVersion()

			try self.validateSource(version: sourceVersion)

			guard sourceVersion == migration.sourceVersion else {
				throw FXCodexError.invalidStorage(
					"expected schema \(migration.sourceVersion) before migration, found \(sourceVersion)"
				)
			}

			let expected = try self.migrationSequence(from: sourceVersion).first

			guard expected == migration else {
				throw FXCodexError.invalidStorage("migration does not match the registered schema sequence")
			}

			try self.perform(migration)

			let destinationVersion = try self.detectVersion()

			guard destinationVersion == migration.destinationVersion else {
				throw FXCodexError.invalidStorage(
					"migration finished at schema \(destinationVersion), expected \(migration.destinationVersion)"
				)
			}
		}
	}

	func migrationPlan() throws -> StorageMigrationPlan? {
		try self.lock.withLock {
			guard self.fileManager.fileExists(atPath: self.paths.configurationURL.path) else {
				return nil
			}

			let sourceVersion = try self.detectVersion()
			if sourceVersion == .v2_0 {
				try self.verifyV2()
				return nil
			}

			let migrations = try self.migrationSequence(from: sourceVersion)
			try self.validateSource(version: sourceVersion)

			return StorageMigrationPlan(
				sourceVersion: sourceVersion,
				destinationVersion: .v2_0,
				migrations: migrations
			)
		}
	}

	private func bootstrap() throws {
		let primaryID = WorkspaceID.generate()
		try self.writeWorkspaceConfiguration(.init(
			id: primaryID,
			name: Workspace.primaryName,
			kind: .primary
		))
		try self.write(
			StorageConfiguration(currentWorkspaceID: primaryID),
			to: self.paths.configurationURL
		)
	}

	private func detectVersion() throws -> SchemaVersion {
		let data = try Data(contentsOf: self.paths.configurationURL)

		guard
			let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
			let value = object["schema_version"]
		else { return .v1_0 }

		guard let string = value as? String, let version = SchemaVersion(string) else {
			throw FXCodexError.invalidStorage("schema_version must use major.minor string format")
		}
		return version
	}

	private func migrationSequence(from sourceVersion: SchemaVersion) throws -> [StorageMigration] {
		var version = sourceVersion
		var migrations: [StorageMigration] = []
		var visited: Set<SchemaVersion> = []

		while version != .v2_0 {
			guard visited.insert(version).inserted else {
				throw FXCodexError.invalidStorage("schema migration sequence contains a cycle at \(version)")
			}

			let migration: StorageMigration = switch version {
			case .v1_0: MigrationV1.migration
			default: throw FXCodexError.unsupportedSchemaVersion(version)
			}

			migrations.append(migration)
			version = migration.destinationVersion
		}

		return migrations
	}

	private func perform(_ migration: StorageMigration) throws {
		switch migration.sourceVersion {
		case .v1_0:
			try self.migrateV1ToV2()

		default:
			throw FXCodexError.unsupportedSchemaVersion(migration.sourceVersion)
		}
	}

	private func validateSource(version: SchemaVersion) throws {
		switch version {
		case .v1_0:
			let configuration = try self.read(LegacyConfiguration.self, from: self.paths.configurationURL)
			var workspaceNames = Set(try self.legacyWorkspaceNames())
			if self.fileManager.fileExists(atPath: self.paths.migrationURL.path) {
				let journal = try self.read(MigrationJournal.self, from: self.paths.migrationURL)
				workspaceNames.formUnion(journal.workspaceIDs.keys)
			}

			guard
				configuration.currentWorkspaceName == Workspace.primaryName
				|| workspaceNames.contains(configuration.currentWorkspaceName)
			else {
				throw FXCodexError.invalidStorage(
					"current_workspace_name does not reference an existing schema 1.0 workspace"
				)
			}

			try self.validateLegacyApplicationInstances(workspaceNames: workspaceNames)

		default:
			throw FXCodexError.unsupportedSchemaVersion(version)
		}
	}

	private func validateLegacyApplicationInstances(workspaceNames: Set<String>) throws {
		guard self.fileManager.fileExists(atPath: self.paths.instancesURL.path) else { return }

		let records = try self.read(
			[String: ApplicationInstanceRecord].self,
			from: self.paths.instancesURL
		)

		for workspaceName in records.keys.sorted()
		where workspaceName != Workspace.primaryName && workspaceNames.contains(workspaceName) {
			guard let record = records[workspaceName] else { continue }
			guard !Self.processExists(record.processID) else {
				throw FXCodexError.workspaceIsRunning(workspaceName)
			}
		}
	}

	private static func processExists(_ processID: Int32) -> Bool {
		guard processID > 0 else { return false }
		if Darwin.kill(processID, 0) == 0 { return true }
		return errno == EPERM
	}

	private func migrateV1ToV2() throws {
		let legacy = try self.read(LegacyConfiguration.self, from: self.paths.configurationURL)
		let journal = try self.loadOrCreateJournal(legacy: legacy)

		for name in journal.workspaceIDs.keys.sorted() {
			guard let id = journal.workspaceIDs[name] else { continue }
			let oldURL = self.paths.workspacesURL.appending(path: name, directoryHint: .isDirectory)
			let newURL = self.workspaceURL(id)
			let oldExists = self.fileManager.fileExists(atPath: oldURL.path)
			let newExists = self.fileManager.fileExists(atPath: newURL.path)
			guard !(oldExists && newExists) else {
				throw FXCodexError.invalidStorage("both legacy and migrated directories exist for workspace \(name)")
			}
			if oldExists {
				try self.write(
					WorkspaceConfiguration(id: id, name: name, kind: .managed),
					to: oldURL.appending(path: "workspace.json")
				)
				try self.fileManager.moveItem(at: oldURL, to: newURL)

			} else if !newExists {
				throw FXCodexError.invalidStorage("legacy workspace directory is missing for \(name)")
			}
		}

		try self.writeWorkspaceConfiguration(.init(
			id: journal.primaryWorkspaceID,
			name: Workspace.primaryName,
			kind: .primary
		))

		let allIDs = journal.workspaceIDs.merging(
			[Workspace.primaryName: journal.primaryWorkspaceID],
			uniquingKeysWith: { first, _ in first }
		)
		let currentID = allIDs[legacy.currentWorkspaceName] ?? journal.primaryWorkspaceID
		let integrations = self.migrateIntegrations(
			legacy.workspaceIntegrations,
			workspaceIDs: allIDs,
			currentWorkspaceName: legacy.currentWorkspaceName
		)

		let legacyInstances = (try? self.read(
			[String: ApplicationInstanceRecord].self,
			from: self.paths.instancesURL
		)) ?? [:]
		let instances = legacyInstances.reduce(into: [WorkspaceID: ApplicationInstanceRecord]()) { result, item in
			guard let id = allIDs[item.key] else { return }
			result[id] = item.value
		}

		try self.write(RuntimeConfiguration(instances: instances), to: self.paths.runtimeURL)
		try self.write(
			StorageConfiguration(currentWorkspaceID: currentID, integrations: integrations),
			to: self.paths.configurationURL
		)
		try? self.fileManager.removeItem(at: self.paths.instancesURL)
		try? self.fileManager.removeItem(at: self.paths.migrationURL)
		try self.verifyV2()
	}

	private func loadOrCreateJournal(legacy: LegacyConfiguration) throws -> MigrationJournal {
		if self.fileManager.fileExists(atPath: self.paths.migrationURL.path) {
			return try self.read(MigrationJournal.self, from: self.paths.migrationURL)
		}

		let names = try self.legacyWorkspaceNames()
		let journal = MigrationJournal(
			sourceVersion: .v1_0,
			destinationVersion: .v2_0,
			primaryWorkspaceID: .generate(),
			workspaceIDs: Dictionary(uniqueKeysWithValues: names.map { ($0, WorkspaceID.generate()) })
		)
		try self.write(journal, to: self.paths.migrationURL)
		return journal
	}

	private func legacyWorkspaceNames() throws -> [String] {
		try self.fileManager.contentsOfDirectory(
			at: self.paths.workspacesURL,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		)
		.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
		.map(\.lastPathComponent)
		.filter { WorkspaceID($0) == nil }
		.sorted()
	}

	private func migrateIntegrations(
		_ legacy: [String: [String: CodableValue]],
		workspaceIDs: [String: WorkspaceID],
		currentWorkspaceName: String
	) -> [String: CodableValue] {
		var result: [String: CodableValue] = [:]
		var automaticScriptCommands: ScriptCommandConfiguration?
		var currentScriptCommands: (configuration: ScriptCommandConfiguration, workspaceID: WorkspaceID)?
		var firstScriptCommands: (configuration: ScriptCommandConfiguration, workspaceID: WorkspaceID)?

		for workspaceName in legacy.keys.sorted() {
			guard
				let workspaceID = workspaceIDs[workspaceName],
				let attributes = legacy[workspaceName]
			else { continue }

			for integrationID in attributes.keys.sorted() {
				guard let value = attributes[integrationID] else { continue }

				var workspaceValue = value

				if integrationID == "raycast", var raycast = Self.dictionary(value) {
					if let automatic = Self.scriptCommandConfiguration(
						from: raycast["automatic_script_commands"],
						requiresEnabled: true
					) {
						automaticScriptCommands = automatic
					}

					if let command = Self.scriptCommandConfiguration(from: raycast["script_command"]) {
						let selection = (configuration: command, workspaceID: workspaceID)
						firstScriptCommands = firstScriptCommands ?? selection
						if workspaceName == currentWorkspaceName { currentScriptCommands = selection }
					}
					raycast.removeValue(forKey: "automatic_script_commands")
					raycast.removeValue(forKey: "script_command")
					workspaceValue = .dictionary(raycast)
				}

				guard
					let dictionary = Self.dictionary(workspaceValue),
					!dictionary.isEmpty
				else { continue }

				var integration = Self.dictionary(result[integrationID]) ?? [:]
				var workspaces = Self.dictionary(integration["workspaces"]) ?? [:]
				workspaces[workspaceID.rawValue] = .dictionary(dictionary)
				integration["workspaces"] = .dictionary(workspaces)
				result[integrationID] = .dictionary(integration)
			}
		}

		if let scriptCommands = automaticScriptCommands {
			var raycast = Self.dictionary(result["raycast"]) ?? [:]
			raycast["script_commands"] = .dictionary([
				"path": .string(scriptCommands.path),
				"executable_path": .string(scriptCommands.executablePath),
			])
			result["raycast"] = .dictionary(raycast)

		} else if let scriptCommands = currentScriptCommands ?? firstScriptCommands {
			var raycast = Self.dictionary(result["raycast"]) ?? [:]
			raycast["script_commands"] = .dictionary([
				"path": .string(scriptCommands.configuration.path),
				"executable_path": .string(scriptCommands.configuration.executablePath),
				"workspace_ids": .array([.string(scriptCommands.workspaceID.rawValue)]),
			])
			result["raycast"] = .dictionary(raycast)
		}

		return result
	}

	private static func scriptCommandConfiguration(
		from value: CodableValue?,
		requiresEnabled: Bool = false
	) -> ScriptCommandConfiguration? {
		guard let dictionary = Self.dictionary(value) else { return nil }
		if requiresEnabled, Self.bool(dictionary["enabled"]) != true { return nil }

		guard
			let path = Self.string(dictionary["directory_path"]),
			let executablePath = Self.string(dictionary["fxcodex_executable_path"])
		else { return nil }

		return .init(path: path, executablePath: executablePath)
	}

	private func verifyV2() throws {
		let configuration = try self.read(StorageConfiguration.self, from: self.paths.configurationURL)
		guard configuration.schemaVersion == .v2_0 else {
			throw FXCodexError.unsupportedSchemaVersion(configuration.schemaVersion)
		}
		let workspaces = try self.workspaceConfigurations()
		guard workspaces.filter({ $0.kind == .primary }).count == 1 else {
			throw FXCodexError.invalidStorage("schema 2.0 requires exactly one primary workspace")
		}
		guard workspaces.contains(where: { $0.id == configuration.currentWorkspaceID }) else {
			throw FXCodexError.invalidStorage("current_workspace_id does not reference an existing workspace")
		}
		guard Set(workspaces.map(\.name)).count == workspaces.count else {
			throw FXCodexError.invalidStorage("workspace names must be unique")
		}
	}

	private func workspaceConfigurations() throws -> [WorkspaceConfiguration] {
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
			let value = try self.read(
				WorkspaceConfiguration.self,
				from: directory.appending(path: "workspace.json")
			)
			guard value.id == id else {
				throw FXCodexError.invalidStorage("workspace directory and metadata IDs do not match")
			}
			return value
		}
	}

	private func writeWorkspaceConfiguration(_ configuration: WorkspaceConfiguration) throws {
		let directory = self.workspaceURL(configuration.id)
		try self.fileManager.createDirectory(
			at: directory,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		try self.write(configuration, to: directory.appending(path: "workspace.json"))
	}

	private func workspaceURL(_ id: WorkspaceID) -> URL {
		self.paths.workspacesURL.appending(path: id.rawValue, directoryHint: .isDirectory)
	}

	private func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
		try self.decoder.decode(type, from: Data(contentsOf: url))
	}

	private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
		try self.fileManager.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		try self.encoder.encode(value).write(to: url, options: [.atomic])
	}

	private static func dictionary(_ value: CodableValue?) -> [String: CodableValue]? {
		guard case let .dictionary(dictionary) = value else { return nil }
		return dictionary
	}

	private static func string(_ value: CodableValue?) -> String? {
		guard case let .string(string) = value else { return nil }
		return string
	}

	private static func bool(_ value: CodableValue?) -> Bool? {
		guard case let .bool(bool) = value else { return nil }
		return bool
	}
}
