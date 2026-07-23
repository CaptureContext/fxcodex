import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient

extension AppCommand {
	internal struct UninstallCommand: AsyncParsableCommand {
		internal enum DataDisposition: String, EnumerableFlag {
			case leaveData = "leave-data"
			case eraseData = "erase-data"
			case deleteData = "delete-data"

			var value: UninstallDataDisposition {
				switch self {
				case .leaveData: .leave
				case .eraseData: .erase
				case .deleteData: .delete
				}
			}
		}

		internal static let configuration: CommandConfiguration = .init(
			commandName: "uninstall",
			abstract: "Uninstall fxcodex and optionally remove its data, with interactive setup by default and required confirmation."
		)

		@Flag(help: "How to handle fxcodex workspace data. Omit to choose interactively.")
		internal var dataDisposition: DataDisposition?

		@Flag(name: .shortAndLong, help: "Confirm without prompting.")
		internal var yes: Bool = false

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "uninstall")

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			@Dependency(\._fxcodexSelfInstallation)
			var installation: SelfInstallationClient

			guard let disposition = try self.resolveDisposition(prompts: prompts) else { return }

			if !self.yes {
				guard try prompts.confirm(self.confirmationMessage(disposition)) == true else { return }
			}

			try await client.uninstallData(disposition)

			let method: SelfUninstallMethod = try installation.uninstall(
				currentExecutableURL()
			)

			let reporter: TerminalReporter = await .init()
			await reporter.success(
				"Uninstalled fxcodex\(method == .homebrew ? " using Homebrew" : "")."
			)
		}
	}
}

extension AppCommand.UninstallCommand {
	private func resolveDisposition(
		prompts: TerminalPromptsClient
	) throws -> UninstallDataDisposition? {
		if let dataDisposition = self.dataDisposition {
			return dataDisposition.value
		}

		guard
			let selection = try prompts.select(
				"What should happen to fxcodex data?",
				[
					.init(
						value: UninstallDataDisposition.leave.rawValue,
						label: "Keep data",
						hint: "remove integrations but retain workspaces and Codex data"
					),
					.init(
						value: UninstallDataDisposition.erase.rawValue,
						label: "Erase workspace data",
						hint: "retain empty workspace definitions"
					),
					.init(
						value: UninstallDataDisposition.delete.rawValue,
						label: "Delete everything",
						hint: "remove the entire fxcodex support directory"
					),
				]
			)
		else { return nil }

		return .init(rawValue: selection)
	}

	private func confirmationMessage(
		_ disposition: UninstallDataDisposition
	) -> String {
		switch disposition {
		case .leave:
			"Uninstall fxcodex and remove its managed integrations?"

		case .erase:
			"Uninstall fxcodex and permanently erase all managed workspace data?"

		case .delete:
			"Uninstall fxcodex and permanently delete all fxcodex data?"
		}
	}
}
