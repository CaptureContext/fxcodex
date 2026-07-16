import Dependencies
import Foundation
import Testing
@_spi(Internals) @testable import FXCodexClient

@Suite("Raycast client")
struct RaycastClientTests {
	@Test("Automatically manages one script command per workspace")
	func automaticWorkspaceLifecycle() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			_ = try await client.createWorkspace("work")

			let status: RaycastScriptCommandStatus = try await client.integrations.raycast.installScriptCommands(
				fixture.scriptsURL,
				fixture.executableURL,
				true,
				true
			)
			#expect(status.managedCommandCount == 2)
			#expect(!FileManager.default.fileExists(
				atPath: fixture.scriptsURL.appending(path: "fxcodex-open-current.sh").path
			))
			let workScriptURL: URL = fixture.scriptsURL.appending(
				path: "fxcodex-open-work.sh"
			)
			let workLightIconURL: URL = fixture.scriptsURL.appending(
				path: "fxcodex-open-work-light.png"
			)
			let workDarkIconURL: URL = fixture.scriptsURL.appending(
				path: "fxcodex-open-work-dark.png"
			)
			let workScriptContents: String = try .init(
				contentsOf: workScriptURL,
				encoding: .utf8
			)
			#expect(workScriptContents.contains(
				"# @raycast.icon ./\(workLightIconURL.lastPathComponent)"
			))
			#expect(workScriptContents.contains(
				"# @raycast.iconDark ./\(workDarkIconURL.lastPathComponent)"
			))
			#expect(try Data(contentsOf: workLightIconURL) == RaycastScriptCommandIcon.light)
			#expect(try Data(contentsOf: workDarkIconURL) == RaycastScriptCommandIcon.dark)

			let createdWorkspace: Workspace = try await client.createWorkspace("personal")
			let personalScriptURL: URL = fixture.scriptsURL.appending(
				path: "fxcodex-open-\(createdWorkspace.name).sh"
			)
			#expect(FileManager.default.fileExists(atPath: personalScriptURL.path))

			let renamedWorkspace: Workspace = try await client.renameWorkspace("work", "work-renamed")
			let renamedScriptURL: URL = fixture.scriptsURL.appending(
				path: "fxcodex-open-\(renamedWorkspace.name).sh"
			)
			#expect(!FileManager.default.fileExists(atPath: workScriptURL.path))
			#expect(!FileManager.default.fileExists(atPath: workLightIconURL.path))
			#expect(!FileManager.default.fileExists(atPath: workDarkIconURL.path))
			#expect(FileManager.default.fileExists(atPath: renamedScriptURL.path))
			#expect(FileManager.default.fileExists(
				atPath: fixture.scriptsURL.appending(
					path: "fxcodex-open-\(renamedWorkspace.name)-light.png"
				).path
			))
			#expect(FileManager.default.fileExists(
				atPath: fixture.scriptsURL.appending(
					path: "fxcodex-open-\(renamedWorkspace.name)-dark.png"
				).path
			))

			let codexHomeURL: URL = try #require(renamedWorkspace.codexHomeURL)
			try "settings".write(
				to: codexHomeURL.appending(path: "config.json"),
				atomically: true,
				encoding: .utf8
			)
			let erasedWorkspace: Workspace = try #require(
				try await client.eraseWorkspaces([renamedWorkspace.name]).first
			)
			#expect(erasedWorkspace.integrations.isEmpty)
			#expect(!FileManager.default.fileExists(atPath: renamedScriptURL.path))
			#expect(try FileManager.default.contentsOfDirectory(atPath: codexHomeURL.path).isEmpty)
			#expect(try await client.workspaces().contains { workspace in
				workspace.name == renamedWorkspace.name
			})

			try await client.deleteWorkspace(createdWorkspace.name)
			#expect(!FileManager.default.fileExists(atPath: personalScriptURL.path))
			#expect(try await client.integrations.raycast.scriptCommandStatus().managedCommandCount == 1)
		}
	}

	@Test("Current-only installation can sync and uninstall safely")
	func currentWorkspaceOnly() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		let updatedExecutableURL: URL = try fixture.makeExecutable(named: "fxcodex-updated")
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let workspace: Workspace = try await client.createWorkspace("work")
			try await client.useWorkspace(workspace.name)

			let installedStatus: RaycastScriptCommandStatus = try await client.integrations.raycast.installScriptCommands(
				fixture.scriptsURL,
				fixture.executableURL,
				true,
				false
			)
			#expect(installedStatus.managedCommandCount == 1)

			let newWorkspace: Workspace = try await client.createWorkspace("personal")
			let newWorkspaceScriptURL: URL = fixture.scriptsURL.appending(
				path: "fxcodex-open-\(newWorkspace.name).sh"
			)
			#expect(!FileManager.default.fileExists(atPath: newWorkspaceScriptURL.path))

			let scriptURL: URL = fixture.scriptsURL.appending(path: "fxcodex-open-work.sh")
			let lightIconURL: URL = fixture.scriptsURL.appending(
				path: "fxcodex-open-work-light.png"
			)
			let darkIconURL: URL = fixture.scriptsURL.appending(
				path: "fxcodex-open-work-dark.png"
			)
			let userScriptURL: URL = fixture.scriptsURL.appending(path: "user-script.sh")
			try "#!/bin/sh\n".write(
				to: userScriptURL,
				atomically: true,
				encoding: .utf8
			)

			let syncedStatus: RaycastScriptCommandStatus = try await client.integrations.raycast.syncScriptCommands(
				updatedExecutableURL
			)
			let scriptContents: String = try .init(contentsOf: scriptURL, encoding: .utf8)
			#expect(syncedStatus.managedCommandCount == 1)
			#expect(scriptContents.contains("'\(updatedExecutableURL.path)'"))
			#expect(scriptContents.contains("open 'work'"))

			let uninstalledStatus: RaycastScriptCommandStatus = try await client.integrations.raycast.uninstallScriptCommands()
			#expect(uninstalledStatus.managedCommandCount == 0)
			#expect(FileManager.default.fileExists(atPath: userScriptURL.path))
			#expect(!FileManager.default.fileExists(atPath: scriptURL.path))
			#expect(!FileManager.default.fileExists(atPath: lightIconURL.path))
			#expect(!FileManager.default.fileExists(atPath: darkIconURL.path))
			#expect(try await client.workspaces().allSatisfy { workspace in
				workspace.integrations["raycast"] == nil
			})
		}
	}

	@Test("Sync requires an installed script command")
	func missingScriptCommand() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			_ = try await client.workspaces()
			await #expect(throws: FXCodexError.raycastScriptCommandDirectoryMissing) {
				try await client.integrations.raycast.syncScriptCommands(fixture.executableURL)
			}
		}
	}
}
