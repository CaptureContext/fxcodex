import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient

extension AppCommand {
	internal struct UpdateCommand: AsyncParsableCommand {
		internal enum Channel: String, EnumerableFlag {
			case patch
			case minor
			case major
			case latest

			var value: UpdateChannel {
				switch self {
				case .patch: .patch
				case .minor: .minor
				case .major: .major
				case .latest: .latest
				}
			}
		}

		internal static let configuration: CommandConfiguration = .init(
			commandName: "update",
			abstract: "Update fxcodex from GitHub Releases."
		)

		@Flag(help: "Update channel. Defaults to --patch.")
		internal var channel: Channel = .patch

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			try await self.run(executableURL: currentExecutableURL())
		}

		internal func run(executableURL: URL) async throws {
			guard !isHomebrewManagedExecutable(executableURL)
			else { throw FXCodexError.homebrewManagedUpdate }
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			guard let currentVersion = SemanticVersion(AppCommand.version)
			else { throw ValidationError("fxcodex has an invalid embedded version.") }
			let result: UpdateResult = try await client.update(
				currentVersion,
				self.channel.value,
				executableURL
			)

			if machineOutputRequested(self.json) {
				try printMachineResponse(result)
				return
			}

			let reporter: TerminalReporter = await .init()
			switch result.outcome {
			case .updated:
				await reporter.success(
					"Updated fxcodex from \(result.previousVersion) to \(result.version)."
				)

			case .alreadyCurrent:
				await reporter.info(
					"fxcodex \(result.version) is already current for the \(self.channel.rawValue) channel."
				)
			}
		}
	}
}
