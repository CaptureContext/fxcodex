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
			try rejectMachineOutput(for: "integrations raycast install")

			@Dependency(\.fxCodexClient) var client: FXCodexClient
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

		@Flag(help: "Generate only the command for the current workspace.")
		internal var currentOnly: Bool = false

		@Flag(name: .shortAndLong, help: "Accept confirmation prompts.")
		internal var yes: Bool = false

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let reporter: TerminalReporter = await .init(assumeYes: self.yes)
			let edition: RaycastEdition = self.beta ? .beta : .stable

			switch self.component {
			case .app:
				try await self.installApplication(
					edition: edition,
					client: client,
					reporter: reporter
				)

			case .scriptCommand:
				try await self.installScriptCommands(
					client: client,
					reporter: reporter
				)

			case nil:
				let applicationStatus: RaycastApplicationStatus = try await client.integrations.raycast.applicationStatus(
					edition
				)

				if applicationStatus.applicationURL == nil {
					guard await reporter.confirm("Install \(edition.displayName)?")
					else { return }
					try await self.installApplication(
						edition: edition,
						client: client,
						reporter: reporter
					)
				}

				if await reporter.confirm("Install fxcodex Script Commands for Raycast?") {
					try await self.installScriptCommands(
						client: client,
						reporter: reporter
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

		@Argument(help: "Component to synchronize.")
		internal var component: Component

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "integrations raycast sync")

			guard self.component == .scriptCommand
			else { throw ValidationError("The app component cannot be synchronized by fxcodex.") }

			@Dependency(\.fxCodexClient) var client: FXCodexClient
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

		@Argument(help: "Component to uninstall.")
		internal var component: Component

		@Flag(name: .shortAndLong, help: "Confirm without prompting.")
		internal var yes: Bool = false

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "integrations raycast uninstall")

			guard self.component == .scriptCommand else {
				throw ValidationError("fxcodex does not uninstall the Raycast application.")
			}

			let reporter: TerminalReporter = await .init(assumeYes: self.yes)
			guard await reporter.confirm("Remove all fxcodex-managed Raycast Script Commands?")
			else { return }

			@Dependency(\.fxCodexClient) var client: FXCodexClient
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
	@MainActor
	private func installApplication(
		edition: RaycastEdition,
		client: FXCodexClient,
		reporter: TerminalReporter
	) async throws {
		let installation: RaycastApplicationInstallation = try await client.integrations.raycast.applicationInstallation(
			edition
		)

		switch installation {
		case let .alreadyInstalled(applicationURL):
			reporter.success("\(edition.displayName) is already installed at \(applicationURL.path).")

		case let .command(invocation):
			reporter.info("Installing \(edition.displayName) using Homebrew…")
			let exitCode: Int32 = try runProcess(invocation)
			guard exitCode == 0
			else { throw ExitCode(exitCode) }
			reporter.success("Installed \(edition.displayName).")

		case let .externalDownload(url):
			reporter.info("Opening the official \(edition.displayName) download…")
			guard NSWorkspace.shared.open(url)
			else { throw CocoaError(.fileNoSuchFile) }
		}
	}

	@MainActor
	private func installScriptCommands(
		client: FXCodexClient,
		reporter: TerminalReporter
	) async throws {
		let existingStatus: RaycastScriptCommandStatus = try await client.integrations.raycast.scriptCommandStatus()
		let directoryPath: String

		if let directory = self.directory {
			directoryPath = directory
		} else if let existingDirectoryURL = existingStatus.directoryURL {
			directoryPath = existingDirectoryURL.path
		} else {
			directoryPath = reporter.ask("Raycast Script Commands directory")
		}

		let expandedPath: String = NSString(string: directoryPath).expandingTildeInPath
		let status: RaycastScriptCommandStatus = try await client.integrations.raycast.installScriptCommands(
			URL(fileURLWithPath: expandedPath),
			currentExecutableURL(),
			true,
			!self.currentOnly
		)
		reporter.success("Installed \(status.managedCommandCount) Raycast Script Commands.")
	}
}
