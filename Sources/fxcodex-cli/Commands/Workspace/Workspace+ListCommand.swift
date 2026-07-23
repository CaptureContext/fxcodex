import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.WorkspaceCommand {
	internal struct List: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "List configured workspaces."
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

			let status: FXCodexStatus = try await client.status()

			if machineOutputRequested(self.json) {
				try printMachineResponse(status.workspaces)
				return
			}

			let reporter: TerminalReporter = await .init()

			for item in status.workspaces {
				let currentMarker: String = item.isCurrent ? "*" : " "
				let processDescription: String = item.processID
					.map { "running · pid \($0)" }
				?? "stopped"

				await reporter.info(
					"\(currentMarker) \(item.workspace.name)\t\(processDescription)"
				)
			}
		}
	}
}
