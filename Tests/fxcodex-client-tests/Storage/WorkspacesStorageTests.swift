import Dependencies
import Foundation
import Testing
@_spi(Internals) @testable import FXCodexClient

@Suite("Workspace storage")
struct WorkspacesStorageTests {
	@Test("Lifecycle preserves current workspace and integration metadata")
	func workspaceLifecycle() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let storage: WorkspacesStorage = .init(fileManager: .default)
			var workspace: Workspace = try storage.createWorkspace(named: "work")
			workspace.integrations["test"] = .dictionary([
				"enabled": .bool(true),
			])
			_ = try storage.saveWorkspace(workspace)
			try storage.useWorkspace(named: workspace.name)
			let configurationData: Data = try .init(contentsOf: fixture.rootURL.appending(
				path: "configuration.json"
			))
			let configuration: [String: Any] = try #require(
				JSONSerialization.jsonObject(with: configurationData) as? [String: Any]
			)
			#expect(Set(configuration.keys) == [
				"current_workspace_name",
				"workspace_integrations",
			])

			let persistedWorkspace: Workspace = try storage.workspace(named: workspace.name)
			#expect(persistedWorkspace.integrations == workspace.integrations)
			#expect(try storage.currentWorkspaceName() == workspace.name)

			let renamedWorkspace: Workspace = try storage.renameWorkspace(
				from: workspace.name,
				to: "work-renamed"
			)
			#expect(renamedWorkspace.integrations == workspace.integrations)
			#expect(try storage.currentWorkspaceName() == renamedWorkspace.name)

			try storage.deleteWorkspace(named: renamedWorkspace.name)
			#expect(try storage.currentWorkspaceName() == Workspace.primaryName)
			#expect(try storage.workspaces().map(\.name) == [Workspace.primaryName])
		}
	}

	@Test("Primary is reserved and names are validated")
	func protectedNames() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let storage: WorkspacesStorage = .init(fileManager: .default)
			#expect(throws: FXCodexError.primaryWorkspaceMutation) {
				try storage.createWorkspace(named: Workspace.primaryName)
			}
			#expect(throws: FXCodexError.primaryWorkspaceMutation) {
				try storage.deleteWorkspace(named: Workspace.primaryName)
			}
			#expect(throws: FXCodexError.invalidWorkspaceName("Work Profile")) {
				try storage.createWorkspace(named: "Work Profile")
			}
		}
	}

	@Test("Missing workspaces are rejected")
	func missingWorkspace() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let storage: WorkspacesStorage = .init(fileManager: .default)
			#expect(throws: FXCodexError.workspaceNotFound("missing")) {
				try storage.workspace(named: "missing")
			}
		}
	}

	@Test("Erase preserves workspace directories while removing their contents and metadata")
	func eraseWorkspace() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let storage: WorkspacesStorage = .init(fileManager: .default)
			var workspace: Workspace = try storage.createWorkspace(named: "work")
			workspace.integrations["test"] = .dictionary([
				"enabled": .bool(true),
			])
			_ = try storage.saveWorkspace(workspace)
			try storage.useWorkspace(named: workspace.name)

			let codexHomeURL: URL = try #require(workspace.codexHomeURL)
			let userDataURL: URL = try #require(workspace.userDataURL)
			let nestedURL: URL = codexHomeURL.appending(
				path: "nested",
				directoryHint: .isDirectory
			)
			try FileManager.default.createDirectory(
				at: nestedURL,
				withIntermediateDirectories: false,
				attributes: nil
			)
			try "settings".write(
				to: nestedURL.appending(path: "config.json"),
				atomically: true,
				encoding: .utf8
			)
			try "session".write(
				to: userDataURL.appending(path: ".session"),
				atomically: true,
				encoding: .utf8
			)

			let erasedWorkspace: Workspace = try storage.eraseWorkspace(named: workspace.name)
			#expect(erasedWorkspace.integrations.isEmpty)
			#expect(try storage.currentWorkspaceName() == workspace.name)
			#expect(try FileManager.default.contentsOfDirectory(atPath: codexHomeURL.path).isEmpty)
			#expect(try FileManager.default.contentsOfDirectory(atPath: userDataURL.path).isEmpty)
			#expect(FileManager.default.fileExists(atPath: codexHomeURL.path))
			#expect(FileManager.default.fileExists(atPath: userDataURL.path))
		}
	}
}
