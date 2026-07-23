import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient

extension AppCommand {
	internal struct StatusCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "status",
			abstract: "Show fxcodex status with optionally expanded sections."
		)

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "List every optional status section. Defaults from FXCODEX_STATUS_ALL."
		)
		internal var all: Bool?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "List preferences. Defaults from FXCODEX_STATUS_LIST_PREFERENCES; -1 disables it even when all is enabled."
		)
		internal var listPreferences: Bool?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "List workspaces. Defaults from FXCODEX_STATUS_LIST_WORKSPACES; -1 disables it even when all is enabled."
		)
		internal var listWorkspaces: Bool?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "List integration status. Defaults from FXCODEX_STATUS_LIST_INTEGRATIONS; -1 disables it even when all is enabled."
		)
		internal var listIntegrations: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let sections: StatusSections = try self.sections()
			let status: FXCodexStatus = try await client.status()

			if machineOutputRequested(self.json) {
				try printMachineResponse(StatusOutput(
					status: status,
					sections: sections
				))
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.info("Current workspace: \(status.currentWorkspace)")
			await reporter.info("Support directory: \(status.supportDirectoryURL.path)")
			await reporter.info(
				"Application: \(status.applicationURL?.path ?? "not found")"
			)

			if sections.preferences {
				await reporter.info("")
				await reporter.info("Preferences:")
				await reporter.info(
					"  \(FXCodexPreference.autoRename.rawValue): \(status.preferences.autoRename ? "enabled" : "disabled")"
				)
				await reporter.info(
					"  \(FXCodexPreference.autoUpdate.rawValue): \(status.preferences.autoUpdate.description)"
				)
			}

			if sections.workspaces {
				await reporter.info("")
				await reporter.info("Workspaces:")
				for workspace in status.workspaces {
					let currentMarker: String = workspace.isCurrent ? "*" : " "
					let processDescription: String = workspace.processID
					.map { "running · pid \($0)" }
					?? "stopped"

					await reporter.info(
						"\(currentMarker) \(workspace.workspace.name)\t\(processDescription)"
					)
				}
			}

			if sections.integrations {
				await reporter.info("")
				await reporter.info("Integrations:")
				for raycast in status.raycastApplications {
					let description: String = raycast.applicationURL == nil
					? "not installed"
					: "installed · \(raycast.version ?? "unknown version")"

					await reporter.info("  \(raycast.edition.displayName): \(description)")
				}
				await reporter.info(
					"  Raycast Script Commands: \(status.raycastScriptCommands.managedCommandCount) managed"
				)
			}
		}
	}
}

extension AppCommand.StatusCommand {
	internal func sections(
		environment: [String: String]? = nil
	) throws -> StatusSections {
		let environment = environment ?? currentEnvironment()
		let environmentAll: Bool? = try environmentSwitch(
			named: "FXCODEX_STATUS_ALL",
			in: environment
		)
		let environmentPreferences: Bool? = try environmentSwitch(
			named: "FXCODEX_STATUS_LIST_PREFERENCES",
			in: environment
		)
		let environmentWorkspaces: Bool? = try environmentSwitch(
			named: "FXCODEX_STATUS_LIST_WORKSPACES",
			in: environment
		)
		let environmentIntegrations: Bool? = try environmentSwitch(
			named: "FXCODEX_STATUS_LIST_INTEGRATIONS",
			in: environment
		)
		let all: Bool = self.all ?? environmentAll ?? false
		return .init(
			preferences: self.listPreferences
			?? environmentPreferences
			?? all,
			workspaces: self.listWorkspaces
			?? environmentWorkspaces
			?? all,
			integrations: self.listIntegrations
			?? environmentIntegrations
			?? all
		)
	}
}
