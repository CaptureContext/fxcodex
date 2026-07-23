import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient
import Testing
@testable
import FXCodexCLI

@Suite("Raycast command")
struct RaycastCommandTests {
	@Test("Install parses the Beta application component")
	func betaApplication() async throws {
		let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
			"app",
			"--beta",
		])
		#expect(command.component == .app)
		#expect(command.beta)
	}

	@Test("Install parses Script Command options")
	func scriptCommand() async throws {
		let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
			"script-command",
			"--directory",
			"/tmp/raycast",
			"--current-only",
			"--yes",
			"--json",
		])
		#expect(command.component == .scriptCommand)
		#expect(command.directory == "/tmp/raycast")
		#expect(command.currentOnly)
		#expect(command.yes)
		#expect(command.json == true)
	}

	@Test("Sync and uninstall accept explicit or interactive Script Command maintenance")
	func maintenanceCommands() async throws {
		let sync: AppCommand.IntegrationsCommand.Raycast.Sync = try .parse([
			"script-command",
		])
		let uninstall: AppCommand.IntegrationsCommand.Raycast.Uninstall = try .parse([
			"script-command",
			"--yes",
		])
		#expect(sync.component == .scriptCommand)
		#expect(uninstall.component == .scriptCommand)
		#expect(uninstall.yes)

		let interactiveSync: AppCommand.IntegrationsCommand.Raycast.Sync = try .parse([])
		let interactiveUninstall: AppCommand.IntegrationsCommand.Raycast.Uninstall = try .parse([])
		#expect(interactiveSync.component == nil)
		#expect(interactiveUninstall.component == nil)
	}

	@Test("Omitted maintenance components are selected interactively")
	func interactiveMaintenanceComponents() async throws {
		let selections = LockIsolated<[String]>([])
		let synchronized = LockIsolated(false)
		let uninstalled = LockIsolated(false)
		var raycast = Integrations.Raycast()
		raycast.syncScriptCommands = { _ in
			synchronized.setValue(true)
			return .init(directoryURL: nil, managedCommandCount: 1)
		}
		raycast.uninstallScriptCommands = {
			uninstalled.setValue(true)
			return .init(directoryURL: nil, managedCommandCount: 0)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
			$0._fxcodexTerminalPrompts = .init(
				select: { _, options in
					selections.withValue { $0.append(contentsOf: options.map(\.value)) }
					return "script-command"
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let sync: AppCommand.IntegrationsCommand.Raycast.Sync = try .parse([])
			try await sync.run()

			let uninstall: AppCommand.IntegrationsCommand.Raycast.Uninstall = try .parse(["--yes"])
			try await uninstall.run()
		}

		#expect(selections.value == ["script-command", "script-command"])
		#expect(synchronized.value)
		#expect(uninstalled.value)
	}

	@Test("Script Command installation executes with machine output without prompting")
	func machineInstallScriptCommand() async throws {
		let didPrompt = LockIsolated(false)
		let installedDirectory = LockIsolated<URL?>(nil)
		var raycast = Integrations.Raycast()
		raycast.scriptCommandStatus = {
			.init(directoryURL: nil, managedCommandCount: 0)
		}
		raycast.installScriptCommands = { directory, _, _ in
			installedDirectory.setValue(directory)
			return .init(directoryURL: directory, managedCommandCount: 2)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in
					didPrompt.setValue(true)
					return nil
				},
				multiselect: { _, _ in
					didPrompt.setValue(true)
					return nil
				},
				confirm: { _ in
					didPrompt.setValue(true)
					return nil
				},
				text: { _, _ in
					didPrompt.setValue(true)
					return nil
				}
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
				"script-command",
				"--directory",
				"/tmp/raycast",
				"--json",
			])
			try await command.run()
		}

		#expect(installedDirectory.value?.path == "/tmp/raycast")
		#expect(!didPrompt.value)
	}

	@Test("Machine installation requires an explicit component")
	func machineInstallRequiresComponent() async throws {
		let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse(["--json"])

		await #expect(throws: ValidationError.self) {
			try await command.run()
		}
	}

	@Test("Application installation executes with machine output")
	func machineInstallApplication() async throws {
		let applicationURL = URL(fileURLWithPath: "/Applications/Raycast.app")
		var raycast = Integrations.Raycast()
		raycast.applicationInstallation = { edition in
			#expect(edition == .stable)
			return .alreadyInstalled(applicationURL)
		}
		raycast.applicationStatus = { edition in
			.init(
				edition: edition,
				applicationURL: applicationURL,
				version: "1.0.0"
			)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
		} operation: {
			let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
				"app",
				"--json",
			])
			try await command.run()
		}
	}

	@Test("Status executes with machine output")
	func machineStatus() async throws {
		var raycast = Integrations.Raycast()
		raycast.applicationStatus = { edition in
			.init(edition: edition, applicationURL: nil, version: nil)
		}
		raycast.scriptCommandStatus = {
			.init(
				directoryURL: URL(fileURLWithPath: "/tmp/raycast"),
				managedCommandCount: 1
			)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
		} operation: {
			let command: AppCommand.IntegrationsCommand.Raycast.Status = try .parse(["--json"])
			try await command.run()
		}
	}
}
