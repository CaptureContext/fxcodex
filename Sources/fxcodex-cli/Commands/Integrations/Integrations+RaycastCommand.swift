import AppKit
import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient

extension AppCommand.IntegrationsCommand.Raycast {
	internal enum Component: String, CaseIterable, ExpressibleByArgument {
		case app
		case scriptCommand = "script-command"
		case raycastExtension = "extension"
	}

	internal enum MaintenanceComponent: String, CaseIterable, ExpressibleByArgument {
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
			abstract: "Install Raycast or an fxcodex integration component."
		)

		@Argument(help: "Component to install; script-command is deprecated. Omit to choose interactively.")
		internal var component: Component?

		@Flag(help: "Target Raycast Beta instead of stable Raycast.")
		internal var beta: Bool = false

		@Option(help: "Raycast Script Commands directory.")
		internal var directory: String?

		@Flag(help: "Generate only the command for the workspace that is currently selected.")
		internal var currentOnly: Bool = false

		@Flag(help: "Open the fxcodex extension page in the default browser.")
		internal var openInBrowser: Bool = false

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

			@Dependency(\._fxcodexExternalURLOpener)
			var externalURLOpener: ExternalURLOpenerClient

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			let json = machineOutputRequested(self.json)

			guard !json || self.component != nil else {
				throw ValidationError("An integration component is required when using --json.")
			}
			guard !self.openInBrowser || self.component == .raycastExtension else {
				throw ValidationError("--open-in-browser is only available for the extension component.")
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

			case .raycastExtension:
				guard let result = try await self.installExtension(
					client: client,
					externalURLOpener: externalURLOpener,
					prompts: prompts,
					reporter: json ? nil : reporter,
					json: json
				) else { return }

				if json {
					try printMachineResponse(Output(
						component: Component.raycastExtension.rawValue,
						outcome: result.outcome,
						application: result.application,
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
				guard let rawComponent = try prompts.select(
					"Choose a component to install:",
					[
						.init(
							value: InteractiveComponent.app.rawValue,
							label: "Raycast",
						),
						.init(
							value: InteractiveComponent.betaApp.rawValue,
							label: "Raycast Beta",
						),
						.init(
							value: InteractiveComponent.scriptCommand.rawValue,
							label: "Script Commands (deprecated)",
							hint: "Use the extension when possible"
						),
						.init(
							value: InteractiveComponent.raycastExtension.rawValue,
							label: "Extension",
							hint: "Install the fxcodex Raycast extension"
						),
					]
				) else { return }

				guard let component = InteractiveComponent(rawValue: rawComponent)
				else { throw ValidationError("Unsupported Raycast installation component.") }

				switch component {
				case .app:
					_ = try await self.installApplication(
						edition: .stable,
						client: client,
						reporter: reporter,
						suppressOutput: false
					)

				case .betaApp:
					_ = try await self.installApplication(
						edition: .beta,
						client: client,
						reporter: reporter,
						suppressOutput: false
					)

				case .scriptCommand:
					_ = try await self.installScriptCommands(
						client: client,
						reporter: reporter,
						json: false
					)

				case .raycastExtension:
					_ = try await self.installExtension(
						client: client,
						externalURLOpener: externalURLOpener,
						prompts: prompts,
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
		internal var component: MaintenanceComponent?

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "integrations raycast sync")

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			guard try AppCommand.IntegrationsCommand.Raycast.resolveMaintenanceComponent(
				self.component,
				action: "synchronize",
				prompts: prompts
			) != nil else { return }

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
		internal var component: MaintenanceComponent?

		@Flag(name: .shortAndLong, help: "Confirm without prompting.")
		internal var yes: Bool = false

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "integrations raycast uninstall")

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			guard try AppCommand.IntegrationsCommand.Raycast.resolveMaintenanceComponent(
				self.component,
				action: "uninstall",
				prompts: prompts
			) != nil else { return }

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
	private enum InteractiveComponent: String {
		case app
		case betaApp = "app-beta"
		case scriptCommand = "script-command"
		case raycastExtension = "extension"
	}

	private enum Outcome: String, Encodable {
		case alreadyInstalled = "already-installed"
		case downloadOpened = "download-opened"
		case extensionOpened = "extension-opened"
		case installed
		case storePageOpened = "store-page-opened"
	}

	private struct Output: Encodable {
		let component: String
		let outcome: Outcome
		let application: RaycastApplicationStatus?
		let scriptCommands: RaycastScriptCommandStatus?
	}

	private struct ExtensionInstallationResult {
		let outcome: Outcome
		let application: RaycastApplicationStatus?

		init(
			outcome: Outcome,
			application: RaycastApplicationStatus?
		) {
			self.outcome = outcome
			self.application = application
		}
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
	private func installExtension(
		client: FXCodexClient,
		externalURLOpener: ExternalURLOpenerClient,
		prompts: TerminalPromptsClient,
		reporter: TerminalReporter?,
		json: Bool
	) async throws -> ExtensionInstallationResult? {
		guard
			let deepLink = URL(string: "raycast://extensions/maximkrouk/fxcodex"),
			let storePageURL = URL(string: "https://www.raycast.com/maximkrouk/fxcodex")
		else { throw CocoaError(.fileNoSuchFile) }

		if self.openInBrowser {
			try externalURLOpener.openInBrowser(storePageURL)
			reporter?.success("Opened the fxcodex extension page in your browser.")
			return .init(outcome: .storePageOpened, application: nil)
		}

		var installedApplications: [RaycastApplicationStatus] = []

		for edition in RaycastEdition.allCases {
			let status: RaycastApplicationStatus = try await client.integrations.raycast.applicationStatus(
				edition
			)
			if status.applicationURL != nil {
				installedApplications.append(status)
			}
		}

		let selectedApplication: RaycastApplicationStatus

		if self.beta {
			guard let beta = installedApplications.first(where: { $0.edition == .beta }) else {
				throw ValidationError(
					"Raycast Beta is not installed. Install it first or use --open-in-browser."
				)
			}
			selectedApplication = beta

		} else if installedApplications.count == 1, let application = installedApplications.first {
			selectedApplication = application

		} else if installedApplications.count > 1 {
			if json {
				guard let stable = installedApplications.first(where: { $0.edition == .stable })
				else { throw ValidationError("Raycast is not installed.") }
				selectedApplication = stable

			} else {
				let options: [TerminalPromptOption] = installedApplications.map { application in
					.init(
						value: application.edition.rawValue,
						label: application.edition.displayName,
						hint: application.version
					)
				}

				guard let selection = try prompts.select(
					"Open the fxcodex extension with:",
					options
				) else { return nil }
				guard
					let edition = RaycastEdition(rawValue: selection),
					let application = installedApplications.first(where: { $0.edition == edition })
				else { throw ValidationError("Unsupported Raycast edition.") }

				selectedApplication = application
			}

		} else {
			if !self.yes {
				guard !json else {
					throw ValidationError(
						"Raycast is not installed. Pass --yes to install it or use --open-in-browser."
					)
				}

				guard let selection = try prompts.select(
					"Raycast is not installed:",
					[
						.init(
							value: "install",
							label: "Install Raycast",
							hint: "Recommended · then open the fxcodex extension"
						),
						.init(
							value: "browser",
							label: "Open in Browser",
							hint: "View the extension without installing Raycast"
						),
					]
				) else { return nil }

				if selection == "browser" {
					try externalURLOpener.openInBrowser(storePageURL)
					reporter?.success("Opened the fxcodex extension page in your browser.")
					return .init(outcome: .storePageOpened, application: nil)
				}

				guard selection == "install"
				else { throw ValidationError("Unsupported extension installation choice.") }
			}

			let installation = try await self.installApplication(
				edition: .stable,
				client: client,
				reporter: reporter,
				suppressOutput: json
			)
			guard installation.status.applicationURL != nil else {
				throw ValidationError("Raycast must finish installing before the extension can be opened.")
			}
			selectedApplication = installation.status
		}

		guard let applicationURL = selectedApplication.applicationURL
		else { throw ValidationError("The selected Raycast application could not be found.") }

		try await externalURLOpener.openInApplication(deepLink, applicationURL)
		reporter?.success("Opened the fxcodex extension in \(selectedApplication.edition.displayName).")

		return .init(
			outcome: .extensionOpened,
			application: selectedApplication
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
		_ provided: MaintenanceComponent?,
		action: String,
		prompts: TerminalPromptsClient
	) throws -> MaintenanceComponent? {
		if let provided { return provided }

		guard let selected = try prompts.select(
			"Select a component to \(action):",
			[
				.init(
					value: MaintenanceComponent.scriptCommand.rawValue,
					label: "Script Commands",
					hint: nil
				),
			]
		) else { return nil }

		guard let component = MaintenanceComponent(rawValue: selected) else {
			throw ValidationError("Unsupported Raycast integration component.")
		}

		return component
	}
}
