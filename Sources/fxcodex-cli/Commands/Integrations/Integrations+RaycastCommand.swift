import AppKit
import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient

extension AppCommand.IntegrationsCommand.Raycast {
	internal enum Component: String, ExpressibleByArgument {
		case app
		case scriptCommand = "script-command"
	}

	internal struct Status: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Show Raycast integration status."
		)

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			var applications: [RaycastApplicationStatus] = []

			for edition in RaycastEdition.allCases {
				applications.append(
					try await client.integrations.raycast.applicationStatus(edition)
				)
			}

			let scripts: RaycastScriptCommandStatus = try await client.integrations.raycast.scriptCommandStatus()

			if machineOutputRequested(self.json) {
				try printMachineResponse(Output(
					applications: applications,
					scriptCommands: scripts
				))
				return
			}

			let reporter: TerminalReporter = await .init()

			for application in applications {
				let description: String = application.applicationURL == nil
				? "not installed"
				: "installed · \(application.version ?? "unknown version")"

				await reporter.info("\(application.edition.displayName): \(description)")
			}

			await reporter.info("Script Commands: \(scripts.managedCommandCount) managed")

			if let directoryURL = scripts.directoryURL {
				await reporter.info("Directory: \(directoryURL.path)")
			}
		}
	}
}

extension AppCommand.IntegrationsCommand.Raycast {
	internal struct Install: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Install Raycast or its fxcodex Script Commands."
		)

		@Argument(help: "Component to install. Omit to start guided setup.")
		internal var component: Component?

		@Flag(help: "Target Raycast Beta instead of stable Raycast.")
		internal var beta: Bool = false

		@Option(help: "Raycast Script Commands directory.")
		internal var directory: String?

		@Flag(help: "Generate only the command for the workspace that is currently selected.")
		internal var currentOnly: Bool = false

		@Flag(name: .shortAndLong, help: "Accept confirmation prompts.")
		internal var yes: Bool = false

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response without prompting. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let json = machineOutputRequested(self.json)

			guard !json || self.component != nil else {
				throw ValidationError("An integration component is required when using --json.")
			}

			let reporter: TerminalReporter = await .init(assumeYes: self.yes)
			let edition: RaycastEdition = self.beta ? .beta : .stable

			switch self.component {
			case .app:
				let result = try await self.installApplication(
					edition: edition,
					client: client,
					reporter: json ? nil : reporter,
					suppressOutput: json
				)

				if json {
					try printMachineResponse(Output(
						component: Component.app.rawValue,
						outcome: result.outcome,
						application: result.status,
						scriptCommands: nil
					))
				}

			case .scriptCommand:
				let status = try await self.installScriptCommands(
					client: client,
					reporter: json ? nil : reporter,
					json: json
				)

				if json {
					try printMachineResponse(Output(
						component: Component.scriptCommand.rawValue,
						outcome: .installed,
						application: nil,
						scriptCommands: status
					))
				}

			case nil:
				let applicationStatus: RaycastApplicationStatus = try await client.integrations.raycast.applicationStatus(
					edition
				)

				if applicationStatus.applicationURL == nil {
					guard await reporter.confirm("Install \(edition.displayName)?") else { return }

					_ = try await self.installApplication(
						edition: edition,
						client: client,
						reporter: reporter,
						suppressOutput: false
					)
				}

				if await reporter.confirm("Install fxcodex Script Commands for Raycast?") {
					_ = try await self.installScriptCommands(
						client: client,
						reporter: reporter,
						json: false
					)
				}
			}
		}
	}
}

extension AppCommand.IntegrationsCommand.Raycast {
	internal struct Sync: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Synchronize an installed integration component."
		)

		@Argument(help: "Component to synchronize. Omit to choose interactively.")
		internal var component: Component?

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "integrations raycast sync")

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			guard let component = try AppCommand.IntegrationsCommand.Raycast.resolveMaintenanceComponent(
				self.component,
				action: "synchronize",
				prompts: prompts
			) else { return }

			guard component == .scriptCommand
			else { throw ValidationError("The app component cannot be synchronized by fxcodex.") }

			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let status: RaycastScriptCommandStatus = try await client.integrations.raycast.syncScriptCommands(
				currentExecutableURL()
			)

			let reporter: TerminalReporter = await .init()
			await reporter.success("Synchronized \(status.managedCommandCount) Script Commands.")
		}
	}

	internal struct Uninstall: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Uninstall an fxcodex-managed integration component with required confirmation."
		)

		@Argument(help: "Component to uninstall. Omit to choose interactively.")
		internal var component: Component?

		@Flag(name: .shortAndLong, help: "Confirm without prompting.")
		internal var yes: Bool = false

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "integrations raycast uninstall")

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			guard let component = try AppCommand.IntegrationsCommand.Raycast.resolveMaintenanceComponent(
				self.component,
				action: "uninstall",
				prompts: prompts
			) else { return }

			guard component == .scriptCommand else {
				throw ValidationError("fxcodex does not uninstall the Raycast application.")
			}

			let reporter: TerminalReporter = await .init(assumeYes: self.yes)

			guard await reporter.confirm("Remove all fxcodex-managed Raycast Script Commands?")
			else { return }

			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			_ = try await client.integrations.raycast.uninstallScriptCommands()
			await reporter.success("Removed fxcodex-managed Raycast Script Commands.")
		}
	}
}

extension AppCommand.IntegrationsCommand.Raycast.Status {
	private struct Output: Encodable {
		let applications: [RaycastApplicationStatus]
		let scriptCommands: RaycastScriptCommandStatus

		init(
			applications: [RaycastApplicationStatus],
			scriptCommands: RaycastScriptCommandStatus
		) {
			self.applications = applications
			self.scriptCommands = scriptCommands
		}
	}
}

extension AppCommand.IntegrationsCommand.Raycast.Install {
	private enum Outcome: String, Encodable {
		case alreadyInstalled = "already-installed"
		case installed
		case downloadOpened = "download-opened"
	}

	private struct Output: Encodable {
		let component: String
		let outcome: Outcome
		let application: RaycastApplicationStatus?
		let scriptCommands: RaycastScriptCommandStatus?
	}

	@MainActor
	private func installApplication(
		edition: RaycastEdition,
		client: FXCodexClient,
		reporter: TerminalReporter?,
		suppressOutput: Bool
	) async throws -> (outcome: Outcome, status: RaycastApplicationStatus) {
		let installation: RaycastApplicationInstallation = try await client.integrations.raycast.applicationInstallation(
			edition
		)
		let outcome: Outcome

		switch installation {
		case let .alreadyInstalled(applicationURL):
			reporter?.success("\(edition.displayName) is already installed at \(applicationURL.path).")
			outcome = .alreadyInstalled

		case let .command(invocation):
			reporter?.info("Installing \(edition.displayName) using Homebrew…")

			let exitCode: Int32 = try runProcess(
				invocation,
				suppressOutput: suppressOutput
			)

			guard exitCode == 0 else { throw ExitCode(exitCode) }

			reporter?.success("Installed \(edition.displayName).")
			outcome = .installed

		case let .externalDownload(url):
			reporter?.info("Opening the official \(edition.displayName) download…")

			guard NSWorkspace.shared.open(url) else { throw CocoaError(.fileNoSuchFile) }
			outcome = .downloadOpened
		}

		return (
			outcome,
			try await client.integrations.raycast.applicationStatus(edition)
		)
	}

	@MainActor
	private func installScriptCommands(
		client: FXCodexClient,
		reporter: TerminalReporter?,
		json: Bool
	) async throws -> RaycastScriptCommandStatus {
		let existingStatus: RaycastScriptCommandStatus = try await client.integrations.raycast.scriptCommandStatus()
		let directoryPath: String

		if let directory = self.directory {
			directoryPath = directory
		} else if let existingDirectoryURL = existingStatus.directoryURL {
			directoryPath = existingDirectoryURL.path
		} else if json {
			throw ValidationError(
				"--directory is required with --json when no Script Commands directory is configured."
			)
		} else {
			guard let reporter else {
				throw ValidationError("Interactive input is unavailable.")
			}
			directoryPath = reporter.ask("Raycast Script Commands directory")
		}

		let expandedPath: String = NSString(string: directoryPath).expandingTildeInPath
		let status: RaycastScriptCommandStatus = try await client.integrations.raycast.installScriptCommands(
			URL(fileURLWithPath: expandedPath),
			currentExecutableURL(),
			self.currentOnly
		)

		reporter?.success("Installed \(status.managedCommandCount) Raycast Script Commands.")
		return status
	}
}

extension AppCommand.IntegrationsCommand.Raycast {
	fileprivate static func resolveMaintenanceComponent(
		_ provided: Component?,
		action: String,
		prompts: TerminalPromptsClient
	) throws -> Component? {
		if let provided { return provided }

		guard let selected = try prompts.select(
			"Select a component to \(action):",
			[
				.init(
					value: Component.scriptCommand.rawValue,
					label: "Script Commands",
					hint: nil
				),
			]
		) else { return nil }

		guard let component = Component(rawValue: selected) else {
			throw ValidationError("Unsupported Raycast integration component.")
		}

		return component
	}
}
