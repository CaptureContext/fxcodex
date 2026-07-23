import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Storage migrator")
struct MigratorTests {
	@Test("Migrates schema 1.0 names, runtime records, and Raycast attributes to stable IDs")
	func v1ToV2() throws {
		let fixture = try ClientTestFixture()
		defer { fixture.remove() }
		let paths = FXCodexPaths(rootURL: fixture.rootURL)
		let legacyWorkspaceURL = paths.workspacesURL.appending(path: "work", directoryHint: .isDirectory)
		try FileManager.default.createDirectory(
			at: legacyWorkspaceURL.appending(path: "codex-home", directoryHint: .isDirectory),
			withIntermediateDirectories: true
		)
		try FileManager.default.createDirectory(
			at: legacyWorkspaceURL.appending(path: "user-data", directoryHint: .isDirectory),
			withIntermediateDirectories: true
		)
		try Data("preserved".utf8).write(to: legacyWorkspaceURL.appending(path: "codex-home/config.json"))
		let legacyDirectoryID = try #require(
			FileManager.default.attributesOfItem(
				atPath: legacyWorkspaceURL.path
			)[.systemFileNumber] as? NSNumber
		)

		let legacyConfiguration: [String: Any] = [
			"current_workspace_name": "work",
			"workspace_integrations": [
				"primary": [
					"raycast": [
						"automatic_script_commands": [
							"enabled": true,
							"directory_path": "/tmp/raycast",
							"fxcodex_executable_path": "/tmp/fxcodex",
						],
					],
				],
				"work": [
					"raycast": [
						"icon": ["type": "raycast", "value": "Folder"],
						"script_command": [
							"directory_path": "/tmp/old-raycast",
							"fxcodex_executable_path": "/tmp/old-fxcodex",
						],
					],
				],
			],
		]
		try JSONSerialization.data(withJSONObject: legacyConfiguration, options: [.prettyPrinted, .sortedKeys])
			.write(to: paths.configurationURL)

		let encoder = FXCodexJSONCoding.encoder()
		encoder.dateEncodingStrategy = .iso8601
		let record = ApplicationInstanceRecord(
			bundleURL: URL(fileURLWithPath: "/Applications/Codex.app"),
			launchDate: Date(timeIntervalSince1970: 1_000),
			processID: .max
		)
		try encoder.encode(["work": record]).write(to: paths.instancesURL)

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = paths
		} operation: {
			let optionalPlan = try Migrator(fileManager: .default).migrationPlan()
			let plan = try #require(optionalPlan)
			#expect(plan.sourceVersion == .v1_0)
			#expect(plan.destinationVersion == .v2_0)
			#expect(plan.migrations.count == 1)
			#expect(!plan.requiresUserInput)

			let storage = WorkspacesStorage(fileManager: .default)
			let workspaces = try storage.workspaces()
			let work = try #require(workspaces.first(where: { $0.name == "work" }))
			#expect(work.kind == .managed)
			#expect(try storage.currentWorkspaceID() == work.id)
			#expect(work.rootURL?.lastPathComponent == work.id.rawValue)
			#expect(FileManager.default.fileExists(atPath: work.codexHomeURL?.appending(path: "config.json").path ?? ""))
			#expect(!FileManager.default.fileExists(atPath: legacyWorkspaceURL.path))
			let migratedRootURL = try #require(work.rootURL)
			let migratedDirectoryID = try #require(
				FileManager.default.attributesOfItem(
					atPath: migratedRootURL.path
				)[.systemFileNumber] as? NSNumber
			)
			#expect(migratedDirectoryID == legacyDirectoryID)

			let attributes = IntegrationAttributesStorage(fileManager: .default)
			#expect(try attributes.value(
				integration: "raycast",
				path: .init("script_commands.path")
			) == .string("/tmp/raycast"))
			#expect(try attributes.value(
				integration: "raycast",
				path: .init("workspaces.[key: \(work.id.rawValue)].icon.value")
			) == .string("Folder"))

			let instances = AppInstancesStorage(fileManager: .default)
			#expect(try instances.record(forWorkspaceID: work.id) == record)
			try storage.prepare()
			#expect(try storage.workspace(named: "work").id == work.id)
		}

		let migrated = try #require(
			JSONSerialization.jsonObject(with: Data(contentsOf: paths.configurationURL)) as? [String: Any]
		)
		#expect(migrated["schema_version"] as? String == "2.0")
		#expect(migrated["current_workspace_id"] is String)
		#expect(!FileManager.default.fileExists(atPath: paths.instancesURL.path))
		#expect(!FileManager.default.fileExists(atPath: paths.migrationURL.path))
	}

	@Test("Refuses to migrate a workspace while its legacy Codex process is running")
	func runningLegacyWorkspace() throws {
		let fixture = try ClientTestFixture()
		defer { fixture.remove() }
		let paths = FXCodexPaths(rootURL: fixture.rootURL)
		let legacyWorkspaceURL = paths.workspacesURL.appending(
			path: "work",
			directoryHint: .isDirectory
		)

		try FileManager.default.createDirectory(
			at: legacyWorkspaceURL,
			withIntermediateDirectories: true
		)
		try Self.writeLegacyConfiguration(
			currentWorkspaceName: "work",
			to: paths.configurationURL
		)

		let encoder = FXCodexJSONCoding.encoder()
		encoder.dateEncodingStrategy = .iso8601
		try encoder.encode([
			"work": ApplicationInstanceRecord(
				bundleURL: URL(fileURLWithPath: "/Applications/Codex.app"),
				launchDate: Date(),
				processID: ProcessInfo.processInfo.processIdentifier
			),
		]).write(to: paths.instancesURL)

		withDependencies {
			$0.context = .live
			$0._fxcodexPaths = paths
		} operation: {
			let migrator = Migrator(fileManager: .default)

			#expect(throws: FXCodexError.workspaceIsRunning("work")) {
				_ = try migrator.migrationPlan()
			}
			#expect(throws: FXCodexError.workspaceIsRunning("work")) {
				try migrator.migrateIfNeeded()
			}
		}

		#expect(FileManager.default.fileExists(atPath: legacyWorkspaceURL.path))
		#expect(!FileManager.default.fileExists(atPath: paths.migrationURL.path))
	}

	@Test("Schema 2.0 ignores legacy shadow directories without deleting them")
	func legacyShadowDirectory() throws {
		let fixture = try ClientTestFixture()
		defer { fixture.remove() }
		let paths = FXCodexPaths(rootURL: fixture.rootURL)

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = paths
		} operation: {
			let storage = WorkspacesStorage(fileManager: .default)
			try storage.prepare()
			let legacyURL = paths.workspacesURL.appending(path: "work", directoryHint: .isDirectory)
			try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: false)
			try Data("preserve".utf8).write(to: legacyURL.appending(path: "marker"))

			#expect(try storage.workspaces().map(\.name) == [Workspace.primaryName])
			#expect(try Migrator(fileManager: .default).migrationPlan() == nil)
			#expect(FileManager.default.fileExists(atPath: legacyURL.appending(path: "marker").path))
		}
	}

	@Test("Preserves a schema 1.0 current-only Raycast installation")
	func currentOnlyRaycast() throws {
		let fixture = try ClientTestFixture()
		defer { fixture.remove() }
		let paths = FXCodexPaths(rootURL: fixture.rootURL)
		let legacyWorkspaceURL = paths.workspacesURL.appending(
			path: "work",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: legacyWorkspaceURL,
			withIntermediateDirectories: true
		)
		let legacyConfiguration: [String: Any] = [
			"current_workspace_name": "work",
			"workspace_integrations": [
				"work": [
					"raycast": [
						"script_command": [
							"directory_path": "/tmp/raycast",
							"fxcodex_executable_path": "/tmp/fxcodex",
						],
					],
				],
			],
		]
		try JSONSerialization.data(
			withJSONObject: legacyConfiguration,
			options: [.prettyPrinted, .sortedKeys]
		).write(to: paths.configurationURL)

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = paths
		} operation: {
			let storage = WorkspacesStorage(fileManager: .default)
			let work = try storage.workspace(named: "work")
			let attributes = IntegrationAttributesStorage(fileManager: .default)

			#expect(try attributes.value(
				integration: "raycast",
				path: .init("script_commands.workspace_ids.[idx: 0]")
			) == .string(work.id.rawValue))
		}
	}

	@Test("Resumes an interrupted migration from its journal")
	func interruptedMigration() throws {
		let fixture = try ClientTestFixture()
		defer { fixture.remove() }
		let paths = FXCodexPaths(rootURL: fixture.rootURL)
		let primaryID = try #require(WorkspaceID("00000000-0000-0000-0000-000000000001"))
		let workID = try #require(WorkspaceID("00000000-0000-0000-0000-000000000002"))

		try Self.writeLegacyConfiguration(currentWorkspaceName: "work", to: paths.configurationURL)
		try Self.writeJournal(
			primaryID: primaryID,
			workspaceIDs: ["work": workID],
			to: paths.migrationURL
		)

		let migratedWorkspaceURL = paths.workspacesURL.appending(
			path: workID.rawValue,
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: migratedWorkspaceURL,
			withIntermediateDirectories: true
		)
		try Self.write(
			WorkspaceConfiguration(id: workID, name: "work", kind: .managed),
			to: migratedWorkspaceURL.appending(path: "workspace.json")
		)
		try Data("preserved".utf8).write(to: migratedWorkspaceURL.appending(path: "marker"))

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = paths
		} operation: {
			let migrator = Migrator(fileManager: .default)
			#expect(try migrator.migrationPlan()?.sourceVersion == .v1_0)

			try migrator.migrateIfNeeded()

			let storage = WorkspacesStorage(fileManager: .default)
			#expect(try storage.workspace(named: "work").id == workID)
			#expect(try storage.currentWorkspaceID() == workID)
		}

		#expect(FileManager.default.fileExists(
			atPath: migratedWorkspaceURL.appending(path: "marker").path
		))
		#expect(!FileManager.default.fileExists(atPath: paths.migrationURL.path))
	}

	@Test("Rejects conflicting legacy and migrated workspace directories")
	func conflictingDirectories() throws {
		let fixture = try ClientTestFixture()
		defer { fixture.remove() }
		let paths = FXCodexPaths(rootURL: fixture.rootURL)
		let primaryID = try #require(WorkspaceID("00000000-0000-0000-0000-000000000001"))
		let workID = try #require(WorkspaceID("00000000-0000-0000-0000-000000000002"))

		try Self.writeLegacyConfiguration(currentWorkspaceName: "work", to: paths.configurationURL)
		try Self.writeJournal(
			primaryID: primaryID,
			workspaceIDs: ["work": workID],
			to: paths.migrationURL
		)
		try FileManager.default.createDirectory(
			at: paths.workspacesURL.appending(path: "work"),
			withIntermediateDirectories: true
		)
		try FileManager.default.createDirectory(
			at: paths.workspacesURL.appending(path: workID.rawValue),
			withIntermediateDirectories: true
		)

		withDependencies {
			$0.context = .live
			$0._fxcodexPaths = paths
		} operation: {
			#expect(throws: FXCodexError.invalidStorage(
				"both legacy and migrated directories exist for workspace work"
			)) {
				try Migrator(fileManager: .default).migrateIfNeeded()
			}
		}
	}

	@Test("Rejects unsupported and malformed migration sources")
	func invalidSources() throws {
		let unsupportedFixture = try ClientTestFixture()
		defer { unsupportedFixture.remove() }
		let unsupportedPaths = FXCodexPaths(rootURL: unsupportedFixture.rootURL)
		try JSONSerialization.data(
			withJSONObject: ["schema_version": "3.0"],
			options: [.prettyPrinted, .sortedKeys]
		).write(to: unsupportedPaths.configurationURL)

		withDependencies {
			$0.context = .live
			$0._fxcodexPaths = unsupportedPaths
		} operation: {
			#expect(throws: FXCodexError.unsupportedSchemaVersion(.init(major: 3, minor: 0))) {
				_ = try Migrator(fileManager: .default).migrationPlan()
			}
		}

		let invalidFixture = try ClientTestFixture()
		defer { invalidFixture.remove() }
		let invalidPaths = FXCodexPaths(rootURL: invalidFixture.rootURL)
		try Self.writeLegacyConfiguration(currentWorkspaceName: "missing", to: invalidPaths.configurationURL)
		try FileManager.default.createDirectory(
			at: invalidPaths.workspacesURL,
			withIntermediateDirectories: true
		)

		withDependencies {
			$0.context = .live
			$0._fxcodexPaths = invalidPaths
		} operation: {
			#expect(throws: FXCodexError.invalidStorage(
				"current_workspace_name does not reference an existing schema 1.0 workspace"
			)) {
				_ = try Migrator(fileManager: .default).migrationPlan()
			}
		}
	}

	private static func writeLegacyConfiguration(
		currentWorkspaceName: String,
		to url: URL
	) throws {
		try JSONSerialization.data(
			withJSONObject: ["current_workspace_name": currentWorkspaceName],
			options: [.prettyPrinted, .sortedKeys]
		).write(to: url)
	}

	private static func writeJournal(
		primaryID: WorkspaceID,
		workspaceIDs: [String: WorkspaceID],
		to url: URL
	) throws {
		try Self.write(
			MigrationJournal(
				sourceVersion: .v1_0,
				destinationVersion: .v2_0,
				primaryWorkspaceID: primaryID,
				workspaceIDs: workspaceIDs
			),
			to: url
		)
	}

	private static func write<Value: Encodable>(_ value: Value, to url: URL) throws {
		let encoder = FXCodexJSONCoding.encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		try encoder.encode(value).write(to: url, options: [.atomic])
	}
}
