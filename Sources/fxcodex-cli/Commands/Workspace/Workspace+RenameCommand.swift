import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.WorkspaceCommand {
	internal struct Rename: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Rename a stopped managed workspace."
		)

		@Argument(help: "New name, or old name when a second argument is supplied. Omit for guided rename.")
		internal var firstName: String?

		@Argument(help: "New name when renaming a specified workspace.")
		internal var secondName: String?

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

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			let json = machineOutputRequested(self.json)

			let oldName: String?
			let newName: String

			if let firstName = self.firstName {
				oldName = self.secondName == nil ? nil : firstName
				newName = self.secondName ?? firstName

			} else if json {
				throw ValidationError("A workspace name is required when using --json.")

			} else {
				let workspaces = try await client.workspaces().filter { $0.kind == .managed }

				guard !workspaces.isEmpty else {
					let reporter = await TerminalReporter()
					await reporter.info("There are no managed workspaces to rename.")
					return
				}

				let options = workspaces.map {
					TerminalPromptOption(value: $0.name, label: $0.name, hint: nil)
				}

				guard
					let selected = try prompts.select("Select a workspace to rename:", options),
					let entered = try prompts.text("New workspace name:", selected)
				else { return }

				oldName = selected
				newName = entered
			}

			let workspace: Workspace = try await client.renameWorkspace(oldName, newName)

			if json {
				try printMachineResponse(workspace)
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success("Renamed workspace to '\(workspace.name)'.")
		}
	}
}
