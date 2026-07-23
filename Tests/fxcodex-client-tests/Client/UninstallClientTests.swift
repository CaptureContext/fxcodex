import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Uninstall client")
struct UninstallClientTests {
	@Test("Leave removes managed integrations while preserving workspace data")
	func leave() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = CodexApplicationSpy().client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let workspace: Workspace = try await client.createWorkspace("work")
			let codexHomeURL: URL = try #require(workspace.codexHomeURL)
			let dataURL: URL = codexHomeURL.appending(path: "data.json")
			try Data("data".utf8).write(to: dataURL)
			_ = try await client.integrations.raycast.installScriptCommands(
				fixture.scriptsURL,
				fixture.executableURL,
				false
			)

			try await client.uninstallData(.leave)

			#expect(FileManager.default.fileExists(atPath: dataURL.path))
			#expect(try await client.workspaces().allSatisfy { $0.integrations.isEmpty })
			#expect(try FileManager.default.contentsOfDirectory(
				at: fixture.scriptsURL,
				includingPropertiesForKeys: nil
			).isEmpty)
		}
	}

	@Test("Erase clears managed data while preserving workspace definitions")
	func erase() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = CodexApplicationSpy().client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let workspace: Workspace = try await client.createWorkspace("work")
			let codexHomeURL: URL = try #require(workspace.codexHomeURL)
			try Data("data".utf8).write(to: codexHomeURL.appending(path: "data.json"))

			try await client.uninstallData(.erase)

			let preservedWorkspace: Workspace = try #require(
				try await client.workspaces().first { $0.name == workspace.name }
			)
			#expect(preservedWorkspace.integrations.isEmpty)
			#expect(try FileManager.default.contentsOfDirectory(atPath: codexHomeURL.path).isEmpty)
		}
	}

	@Test("Delete removes the complete support directory")
	func delete() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = CodexApplicationSpy().client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			_ = try await client.createWorkspace("work")

			try await client.uninstallData(.delete)

			#expect(!FileManager.default.fileExists(atPath: fixture.rootURL.path))
		}
	}

	@Test("Destructive cleanup refuses to mutate running workspaces")
	func runningWorkspace() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(processIDs: ["work": 42])
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			_ = try await client.createWorkspace("work")

			await #expect(throws: FXCodexError.workspaceIsRunning("work")) {
				try await client.uninstallData(.erase)
			}
			#expect(FileManager.default.fileExists(atPath: fixture.rootURL.path))
		}
	}
}
