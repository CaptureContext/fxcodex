import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.PreferencesCommand {
	internal struct List: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "List fxcodex preferences."
		)

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let preferences: FXCodexPreferences = try await client.preferences()

			if machineOutputRequested(self.json) {
				try printMachineResponse(preferences)
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.info(
				"\(FXCodexPreference.autoRename.rawValue): \(preferences.autoRename ? "enabled" : "disabled")"
			)
			await reporter.info(
				"\(FXCodexPreference.autoUpdate.rawValue): \(preferences.autoUpdate.description)"
			)
		}
	}
}
