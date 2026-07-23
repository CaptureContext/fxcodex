import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Codex application client")
struct CodexApplicationClientTests {
	@Test("Opening delegates to the injected application client")
	func openWorkspace() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(openedProcessID: 7_007)
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let workspace: Workspace = try await client.createWorkspace("work")
			#expect(try await client.openWorkspace(workspace.name) == 7_007)
		}

		#expect(await application.snapshot().openedWorkspaceNames == ["work"])
	}

	@Test("Status is assembled from injected application and integration clients")
	func status() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(
			applicationURL: fixture.applicationURL,
			processIDs: [
				Workspace.primaryName: 101,
				"work": 202,
			]
		)
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			_ = try await client.createWorkspace("work")
			let status: FXCodexStatus = try await client.status()

			#expect(status.applicationURL == fixture.applicationURL)
			#expect(status.currentWorkspace == Workspace.primaryName)
			#expect(status.preferences == .init(autoRename: false))
			#expect(status.supportDirectoryURL == fixture.rootURL.standardizedFileURL)
			#expect(status.workspaces.map(\.processID) == [101, 202])
			#expect(status.raycastApplications.map(\.edition) == [.stable, .beta])
			#expect(status.raycastScriptCommands.managedCommandCount == 0)
		}
	}
}
