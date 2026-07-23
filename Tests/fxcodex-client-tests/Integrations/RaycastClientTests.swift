import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

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
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let work = try await client.createWorkspace("work")

			let status: RaycastScriptCommandStatus = try await client.integrations.raycast.installScriptCommands(
				fixture.scriptsURL,
				fixture.executableURL,
				false
			)
			#expect(status.managedCommandCount == 2)
			let generatedDirectoryURL = fixture.scriptsURL.appending(path: "fxcodex")
			let workScriptURL: URL = generatedDirectoryURL.appending(
				path: "\(work.id.rawValue).sh"
			)
			let workLightIconURL: URL = generatedDirectoryURL.appending(
				path: "\(work.id.rawValue)-light.png"
			)
			let workDarkIconURL: URL = generatedDirectoryURL.appending(
				path: "\(work.id.rawValue)-dark.png"
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
			#expect(workScriptContents.contains("open --workspace-id '\(work.id.rawValue)'"))

			let createdWorkspace: Workspace = try await client.createWorkspace("personal")
			let personalScriptURL: URL = generatedDirectoryURL.appending(
				path: "\(createdWorkspace.id.rawValue).sh"
			)
			#expect(FileManager.default.fileExists(atPath: personalScriptURL.path))

			let renamedWorkspace: Workspace = try await client.renameWorkspace("work", "work-renamed")
			#expect(renamedWorkspace.id == work.id)
			#expect(FileManager.default.fileExists(atPath: workScriptURL.path))
			#expect(try String(contentsOf: workScriptURL, encoding: .utf8).contains("Codex (Work-Renamed)"))

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
			#expect(FileManager.default.fileExists(atPath: workScriptURL.path))
			#expect(try FileManager.default.contentsOfDirectory(atPath: codexHomeURL.path).isEmpty)
			#expect(try await client.workspaces().contains { workspace in
				workspace.name == renamedWorkspace.name
			})

			try await client.deleteWorkspace(createdWorkspace.name)
			#expect(!FileManager.default.fileExists(atPath: personalScriptURL.path))
			#expect(try await client.integrations.raycast.scriptCommandStatus().managedCommandCount == 2)
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
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let workspace: Workspace = try await client.createWorkspace("work")
			try await client.useWorkspace(workspace.name)

			let installedStatus: RaycastScriptCommandStatus = try await client.integrations.raycast.installScriptCommands(
				fixture.scriptsURL,
				fixture.executableURL,
				true
			)
			#expect(installedStatus.managedCommandCount == 1)

			let newWorkspace: Workspace = try await client.createWorkspace("personal")
			let generatedDirectoryURL = fixture.scriptsURL.appending(path: "fxcodex")
			let newWorkspaceScriptURL: URL = generatedDirectoryURL.appending(
				path: "\(newWorkspace.id.rawValue).sh"
			)
			#expect(!FileManager.default.fileExists(atPath: newWorkspaceScriptURL.path))

			let scriptURL: URL = generatedDirectoryURL.appending(path: "\(workspace.id.rawValue).sh")
			let lightIconURL: URL = generatedDirectoryURL.appending(
				path: "\(workspace.id.rawValue)-light.png"
			)
			let darkIconURL: URL = generatedDirectoryURL.appending(
				path: "\(workspace.id.rawValue)-dark.png"
			)
			let userScriptURL: URL = generatedDirectoryURL.appending(path: "user-script.sh")
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
			#expect(scriptContents.contains("open --workspace-id '\(workspace.id.rawValue)'"))

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
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			_ = try await client.workspaces()
			await #expect(throws: FXCodexError.raycastScriptCommandDirectoryMissing) {
				try await client.integrations.raycast.syncScriptCommands(fixture.executableURL)
			}
		}
	}
}
