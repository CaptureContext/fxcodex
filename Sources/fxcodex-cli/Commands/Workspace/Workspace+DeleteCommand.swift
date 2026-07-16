import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.WorkspaceCommand {
	internal struct Delete: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Delete managed workspaces and their data, with interactive selection by default and required confirmation."
		)

		@Argument(help: "Workspace names. Omit to select interactively.")
		internal var names: [String] = []

		@Flag(name: .shortAndLong, help: "Confirm without prompting.")
		internal var yes: Bool = false

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response without prompting. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			@Dependency(\._fxcodexTerminalPrompts) var prompts: TerminalPromptsClient
			let json: Bool = machineOutputRequested(self.json)
			let names: [String]
			if self.names.isEmpty {
				guard !json else {
					throw ValidationError("At least one workspace name is required when using --json.")
				}

				let workspaces: [Workspace] = try await client.workspaces().filter { workspace in
					workspace.kind == .managed
				}
				guard !workspaces.isEmpty else {
					let reporter: TerminalReporter = await .init()
					await reporter.info("There are no managed workspaces to delete.")
					return
				}
				let options: [TerminalPromptOption] = workspaces.map { workspace in
					.init(
						value: workspace.name,
						label: workspace.name,
						hint: nil
					)
				}
				guard let selectedNames = try prompts.multiselect(
					"Select workspaces to delete:",
					options
				) else { return }
				names = selectedNames
			} else {
				names = self.names.uniqued()
			}

			guard !json || self.yes else {
				throw ValidationError("--yes is required with --json when deleting workspaces.")
			}

			guard try self.yes || (prompts.confirm(
				"Delete \(names.workspaceDescription) and all of their managed data?"
			) == true) else {
				let reporter: TerminalReporter = await .init()
				await reporter.warning("Cancelled.")
				return
			}

			try await client.deleteWorkspaces(names)
			if json {
				try printMachineResponse(WorkspaceNamesOutput(workspaceNames: names))
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success("Deleted \(names.workspaceDescription).")
		}
	}
}
