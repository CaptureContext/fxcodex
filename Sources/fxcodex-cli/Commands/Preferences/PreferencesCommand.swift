import ArgumentParser

extension AppCommand {
	internal struct PreferencesCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "preferences",
			abstract: "View and update fxcodex preferences.",
			subcommands: [
				List.self,
				Set.self,
			],
			defaultSubcommand: List.self
		)

		internal init() {}
	}
}
