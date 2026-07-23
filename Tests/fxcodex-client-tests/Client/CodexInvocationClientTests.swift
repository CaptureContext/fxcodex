import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Codex invocation client")
struct CodexInvocationClientTests {
	@Test("Isolates only managed workspace invocations")
	func workspaceEnvironment() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let primaryInvocation: CommandInvocation = try await client.codexInvocation(
				Workspace.primaryName,
				["--version"]
			)
			#expect(primaryInvocation == .init(
				executable: "codex",
				arguments: ["--version"],
				environment: [:]
			))

			let workspace: Workspace = try await client.createWorkspace("work")
			let managedInvocation: CommandInvocation = try await client.codexInvocation(
				workspace.name,
				["exec", "hello"]
			)
			#expect(managedInvocation == .init(
				executable: "codex",
				arguments: ["exec", "hello"],
				environment: [
					"CODEX_HOME": try #require(workspace.codexHomeURL).path,
				]
			))
		}
	}

	@Test("Rejects an unknown workspace")
	func missingWorkspace() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			await #expect(throws: FXCodexError.workspaceNotFound("missing")) {
				try await client.codexInvocation("missing", [])
			}
		}
	}
}
