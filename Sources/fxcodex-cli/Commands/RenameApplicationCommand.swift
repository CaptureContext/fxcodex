import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand {
	internal struct RenameApplicationCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "rename",
			abstract: "Rename the Codex application bundle."
		)

		@Flag(help: "Restore the ChatGPT.app name instead of Codex.app.")
		internal var undo: Bool = false

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let requestedName: CodexApplicationName = self.undo ? .chatGPT : .codex
			let result: CodexApplicationRenameResult = try await client.renameApplication(
				requestedName
			)

			if machineOutputRequested(self.json) {
				try printMachineResponse(result)
				return
			}

			let reporter: TerminalReporter = await .init()
			switch result.outcome {
			case .renamed:
				await reporter.success(
					"Renamed \(requestedName.alternative.rawValue) to \(requestedName.rawValue)."
				)

			case .alreadyNamed:
				await reporter.info(
					"\(requestedName.rawValue) is already present at \(result.applicationURL.path)."
				)

			case .conflict:
				await reporter.warning(
					"Both ChatGPT.app and Codex.app are present. No application was renamed."
				)
			}
		}
	}
}
