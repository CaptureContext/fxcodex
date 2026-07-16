import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.WorkspaceCommand {
	internal struct Create: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Create a managed workspace."
		)

		@Argument(help: "Workspace name.")
		internal var name: String

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
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let workspace: Workspace = try await client.createWorkspace(self.name)

			if self.use {
				try await client.useWorkspace(workspace.name)
			}

			if self.open {
				_ = try await client.openWorkspace(workspace.name)
			}

			if machineOutputRequested(self.json) {
				try printMachineResponse(workspace)
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success("Created workspace '\(workspace.name)'.")
		}
	}
}
