import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.WorkspaceCommand {
	internal struct Rename: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Rename a stopped managed workspace."
		)

		@Argument(help: "New name, or old name when a second argument is supplied.")
		internal var firstName: String

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
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let oldName: String? = self.secondName == nil ? nil : self.firstName
			let newName: String = self.secondName ?? self.firstName
			let workspace: Workspace = try await client.renameWorkspace(oldName, newName)
			if machineOutputRequested(self.json) {
				try printMachineResponse(workspace)
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success("Renamed workspace to '\(workspace.name)'.")
		}
	}
}
