import Dependencies
import Foundation
import Testing
@_spi(Internals) @testable import FXCodexClient

@Suite("Workspace client")
struct WorkspaceClientTests {
	@Test("Creates, selects, renames, and deletes a workspace")
	func lifecycle() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let workspace: Workspace = try await client.createWorkspace("work")
			#expect(workspace.kind == .managed)
			#expect(try await client.workspaces().map(\.name) == ["primary", "work"])

			try await client.useWorkspace(workspace.name)
			#expect(try await client.currentWorkspace().name == workspace.name)

			let renamedWorkspace: Workspace = try await client.renameWorkspace(
				workspace.name,
				"work-renamed"
			)
			#expect(renamedWorkspace.name == "work-renamed")
			#expect(try await client.currentWorkspace().name == renamedWorkspace.name)

			try await client.deleteWorkspace(renamedWorkspace.name)
			#expect(try await client.workspaces().map(\.name) == [Workspace.primaryName])
			#expect(try await client.currentWorkspace().name == Workspace.primaryName)
		}

		let snapshot: CodexApplicationSpy.Snapshot = await application.snapshot()
		#expect(snapshot.renamedWorkspaces == [.init(
			oldName: "work",
			newName: "work-renamed"
		)])
		#expect(snapshot.removedWorkspaceNames == ["work-renamed"])
	}

	@Test("Rejects mutation while a workspace is running")
	func runningWorkspace() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let workspace: Workspace = try await client.createWorkspace("work")
			await application.setProcessID(9_001, forWorkspaceNamed: workspace.name)

			await #expect(throws: FXCodexError.workspaceIsRunning(workspace.name)) {
				try await client.renameWorkspace(workspace.name, "renamed")
			}
			await #expect(throws: FXCodexError.workspaceIsRunning(workspace.name)) {
				try await client.deleteWorkspace(workspace.name)
			}
			#expect(try await client.workspaces().map(\.name) == ["primary", "work"])
		}
	}

	@Test("Batch deletion validates every workspace before deleting any")
	func batchDeletionPreflight() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let work: Workspace = try await client.createWorkspace("work")
			let personal: Workspace = try await client.createWorkspace("personal")
			await application.setProcessID(9_001, forWorkspaceNamed: personal.name)

			await #expect(throws: FXCodexError.workspaceIsRunning(personal.name)) {
				try await client.deleteWorkspaces([work.name, personal.name])
			}
			#expect(try await client.workspaces().map(\.name) == [
				Workspace.primaryName,
				personal.name,
				work.name,
			])

			await application.setProcessID(nil, forWorkspaceNamed: personal.name)
			try await client.deleteWorkspaces([
				work.name,
				personal.name,
				work.name,
			])
			#expect(try await client.workspaces().map(\.name) == [Workspace.primaryName])
		}
	}
}
