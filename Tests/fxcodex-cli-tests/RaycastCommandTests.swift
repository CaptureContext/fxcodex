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

	@Test("Install parses the extension browser override")
	func extensionBrowserOverride() throws {
		let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
			"extension",
			"--open-in-browser",
		])
		#expect(command.component == .raycastExtension)
		#expect(command.openInBrowser)
	}

	@Test("Component command help lists accepted values")
	func componentHelp() {
		let installHelp: String = AppCommand.IntegrationsCommand.Raycast.Install.helpMessage()
		let syncHelp: String = AppCommand.IntegrationsCommand.Raycast.Sync.helpMessage()
		let uninstallHelp: String = AppCommand.IntegrationsCommand.Raycast.Uninstall.helpMessage()

		#expect(installHelp.contains("(values: app,"))
		#expect(installHelp.contains("script-command, extension)"))
		#expect(installHelp.contains("script-command is deprecated"))
		#expect(syncHelp.contains("values: script-command"))
		#expect(uninstallHelp.contains("values: script-command"))
	}

	@Test("Integrations can enter the interactive Raycast status action")
	func interactiveIntegrationsRaycastStatus() async throws {
		let offeredValues = LockIsolated<[[String]]>([])
		let answers = LockIsolated(["raycast", "status"])
		let statusRequested = LockIsolated(false)
		var raycast = Integrations.Raycast()
		raycast.applicationStatus = { edition in
			statusRequested.setValue(true)
			return .init(edition: edition, applicationURL: nil, version: nil)
		}
		raycast.scriptCommandStatus = {
			.init(directoryURL: nil, managedCommandCount: 0)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
			$0._fxcodexTerminalPrompts = .init(
				select: { _, options in
					offeredValues.withValue { $0.append(options.map(\.value)) }
					return answers.withValue { $0.removeFirst() }
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand = try .parse([])
			try await command.run()
		}

		#expect(offeredValues.value == [
			["attributes", "raycast"],
			["status", "install"],
		])
		#expect(statusRequested.value)
	}

	@Test("Bare Raycast command offers actions")
	func interactiveRaycastActions() async throws {
		let offeredValues = LockIsolated<[String]>([])
		var raycast = Integrations.Raycast()
		raycast.applicationStatus = { edition in
			.init(edition: edition, applicationURL: nil, version: nil)
		}
		raycast.scriptCommandStatus = {
			.init(directoryURL: nil, managedCommandCount: 0)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
			$0._fxcodexTerminalPrompts = .init(
				select: { _, options in
					offeredValues.setValue(options.map(\.value))
					return "status"
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let parsed: any ParsableCommand = try AppCommand.parseAsRoot([
				"integrations",
				"raycast",
			])
			let command = try #require(parsed as? AppCommand.IntegrationsCommand.Raycast)
			try await command.run()
		}

		#expect(offeredValues.value == ["status", "install"])
	}

	@Test("Interactive installation offers every component")
	func interactiveInstallComponents() async throws {
		let applicationURL = URL(fileURLWithPath: "/Applications/Raycast.app")
		let offeredOptions = LockIsolated<[TerminalPromptOption]>([])
		var raycast = Integrations.Raycast()
		raycast.applicationInstallation = { edition in
			#expect(edition == .stable)
			return .alreadyInstalled(applicationURL)
		}
		raycast.applicationStatus = { edition in
			.init(
				edition: edition,
				applicationURL: edition == .stable ? applicationURL : nil,
				version: nil
			)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
			$0._fxcodexTerminalPrompts = .init(
				select: { _, options in
					offeredOptions.setValue(options)
					return "app"
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([])
			try await command.run()
		}

		#expect(offeredOptions.value.map(\.value) == [
			"app",
			"app-beta",
			"script-command",
			"extension",
		])
		#expect(offeredOptions.value.map(\.label) == [
			"Raycast",
			"Raycast Beta",
			"Script Commands (deprecated)",
			"Extension",
		])
	}

	@Test("Extension browser override opens the Raycast Store page directly")
	func openExtensionInBrowser() async throws {
		let openedURL = LockIsolated<URL?>(nil)

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexExternalURLOpener = .init(
				openInApplication: { _, _ in },
				openInBrowser: { openedURL.setValue($0) }
			)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in nil },
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
				"extension",
				"--open-in-browser",
			])
			try await command.run()
		}

		#expect(openedURL.value?.absoluteString == "https://www.raycast.com/maximkrouk/fxcodex")
	}

	@Test("Extension installation selects an installed Raycast edition")
	func selectInstalledApplicationForExtension() async throws {
		let betaURL = URL(fileURLWithPath: "/Applications/Raycast Beta.app")
		let openedDeepLink = LockIsolated<URL?>(nil)
		let openedApplicationURL = LockIsolated<URL?>(nil)
		let offeredEditions = LockIsolated<[String]>([])
		var raycast = Integrations.Raycast()
		raycast.applicationStatus = { edition in
			.init(
				edition: edition,
				applicationURL: URL(fileURLWithPath: edition == .stable
					? "/Applications/Raycast.app"
					: betaURL.path),
				version: edition == .stable ? "1.2.3" : "1.2.4-beta"
			)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
			$0._fxcodexExternalURLOpener = .init(
				openInApplication: { deepLink, applicationURL in
					openedDeepLink.setValue(deepLink)
					openedApplicationURL.setValue(applicationURL)
				},
				openInBrowser: { _ in }
			)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, options in
					offeredEditions.setValue(options.map(\.value))
					return RaycastEdition.beta.rawValue
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
				"extension",
			])
			try await command.run()
		}

		#expect(offeredEditions.value == ["stable", "beta"])
		#expect(openedDeepLink.value?.absoluteString == "raycast://extensions/maximkrouk/fxcodex")
		#expect(openedApplicationURL.value == betaURL)
	}

	@Test("Extension installation recommends Raycast with a browser fallback")
	func recommendRaycastForExtension() async throws {
		let offeredChoices = LockIsolated<[String]>([])
		let openedURL = LockIsolated<URL?>(nil)
		var raycast = Integrations.Raycast()
		raycast.applicationStatus = { edition in
			.init(edition: edition, applicationURL: nil, version: nil)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
			$0._fxcodexExternalURLOpener = .init(
				openInApplication: { _, _ in },
				openInBrowser: { openedURL.setValue($0) }
			)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, options in
					offeredChoices.setValue(options.map(\.value))
					return "browser"
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
				"extension",
			])
			try await command.run()
		}

		#expect(offeredChoices.value == ["install", "browser"])
		#expect(openedURL.value?.absoluteString == "https://www.raycast.com/maximkrouk/fxcodex")
	}

	@Test("Extension installation can install Raycast before opening")
	func installRaycastForExtension() async throws {
		let applicationURL = URL(fileURLWithPath: "/Applications/Raycast.app")
		let didInstall = LockIsolated(false)
		let didPrompt = LockIsolated(false)
		let openedDeepLink = LockIsolated<URL?>(nil)
		let openedApplicationURL = LockIsolated<URL?>(nil)
		var raycast = Integrations.Raycast()
		raycast.applicationStatus = { edition in
			.init(
				edition: edition,
				applicationURL: edition == .stable && didInstall.value
					? applicationURL
					: nil,
				version: nil
			)
		}
		raycast.applicationInstallation = { edition in
			#expect(edition == .stable)
			didInstall.setValue(true)
			return .alreadyInstalled(applicationURL)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: raycast, attributes: .init())
			$0._fxcodexExternalURLOpener = .init(
				openInApplication: { deepLink, applicationURL in
					openedDeepLink.setValue(deepLink)
					openedApplicationURL.setValue(applicationURL)
				},
				openInBrowser: { _ in }
			)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in
					didPrompt.setValue(true)
					return nil
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
				"extension",
				"--yes",
			])
			try await command.run()
		}

		#expect(didInstall.value)
		#expect(!didPrompt.value)
		#expect(openedDeepLink.value?.absoluteString == "raycast://extensions/maximkrouk/fxcodex")
		#expect(openedApplicationURL.value == applicationURL)
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
