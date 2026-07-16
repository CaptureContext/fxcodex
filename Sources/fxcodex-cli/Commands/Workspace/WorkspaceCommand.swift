import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand {
	internal struct WorkspaceCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "workspace",
			abstract: "Manage isolated Codex workspaces.",
			subcommands: [
				List.self,
				Create.self,
				Delete.self,
				Erase.self,
				Rename.self,
				Use.self,
				OpenCommand.self,
			],
			defaultSubcommand: List.self
		)

		internal init() {}
	}
}
