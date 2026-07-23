import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.WorkspaceCommand {
	internal struct Create: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Create a managed workspace."
		)

		@Argument(help: "Workspace name. Omit to enter interactively.")
		internal var name: String?

		@Flag(help: "Make the new workspace current.")
		internal var use: Bool = false

		@Flag(help: "Open the new workspace after creating it.")
		internal var open: Bool = false

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

			let name: String

			if let provided = self.name {
				name = provided
			} else if json {
				throw ValidationError("A workspace name is required when using --json.")
			} else if let entered = try prompts.text("Workspace name:", "work") {
				name = entered
			} else { return }

			let workspace: Workspace = try await client.createWorkspace(name)

			if self.use {
				try await client.useWorkspace(workspace.name)
			}

			if self.open {
				_ = try await client.openWorkspace(workspace.name)
			}

			if json {
				try printMachineResponse(workspace)
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success("Created workspace '\(workspace.name)'.")
		}
	}
}
