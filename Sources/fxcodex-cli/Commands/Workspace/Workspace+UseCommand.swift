import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.WorkspaceCommand {
	internal struct Use: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Set the current workspace."
		)

		@Argument(help: "Workspace name. Omit to choose interactively.")
		internal var name: String?

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

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			let json: Bool = machineOutputRequested(self.json)

			let name: String

			if let providedName = self.name {
				name = providedName

			} else if json {
				throw ValidationError("A workspace name is required when using --json.")

			} else {
				let currentWorkspace: Workspace = try await client.currentWorkspace()
				let options: [TerminalPromptOption] = try await client.workspaces().map { workspace in
					.init(
						value: workspace.name,
						label: workspace.name,
						hint: workspace.name == currentWorkspace.name ? "current" : nil
					)
				}

				guard let selectedName = try prompts.select(
					"Select a workspace to use:",
					options
				) else { return }

				name = selectedName
			}

			try await client.useWorkspace(name)

			if json {
				try printMachineResponse(try await client.currentWorkspace())
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success("Current workspace is now '\(name)'.")
		}
	}
}
