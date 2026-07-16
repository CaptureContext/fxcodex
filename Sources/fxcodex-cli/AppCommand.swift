import ArgumentParser
import Dependencies
import Darwin
import Foundation
import FXCodexClient

@main
internal struct AppCommand: AsyncParsableCommand {
	internal static let version: String = "0.1.0"
	internal static let machineEncodingFailureResponse: String = """
		{
		  "api_version": 1,
		  "error": {
		    "code": "encoding_failed",
		    "message": "Unable to encode the error response."
		  },
		  "ok": false
		}
		"""

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print versioned machine-readable JSON from supported commands. Defaults from FXCODEX_JSON."
	)
	internal var json: Bool?

	internal static let configuration: CommandConfiguration = .init(
		commandName: "fxcodex",
		abstract: "Manage isolated Codex workspaces and integrations.",
		version: Self.version,
			subcommands: [
			WorkspaceCommand.self,
			PreferencesCommand.self,
			WorkspaceCommand.Use.self,
			WorkspaceCommand.Delete.self,
			WorkspaceCommand.Erase.self,
			RenameApplicationCommand.self,
			OpenCommand.self,
			CLICommand.self,
			ExecCommand.self,
			StatusCommand.self,
			UpdateCommand.self,
			UninstallCommand.self,
			IntegrationsCommand.self,
			VersionCommand.self,
		],
		defaultSubcommand: nil
	)

	internal init() {}

	internal static func main() async {
		do {
			let command: any ParsableCommand = try await Self.asyncParseAsRoot()
			let warnings: [FXCodexWarning] = try await Self.prepareForExecution(command)

			if globalMachineOutputRequested() {
				for warning in warnings {
					try printMachineWarning(warning)
				}
			} else {
				let reporter: TerminalReporter = .init()
				for warning in warnings {
					reporter.warning(warning.message)
				}
			}
			try await Self.execute(command)
		} catch {
			guard globalMachineOutputRequested(), !(error is CleanExit) else {
				Self.exit(withError: error)
			}

			do {
				try printMachineError(error)
			} catch {
				FileHandle.standardError.write(
					Data("\(Self.machineEncodingFailureResponse)\n".utf8)
				)
			}

			Darwin.exit(Self.exitCode(for: error).rawValue)
		}
	}

	internal static func prepareForExecution(
		_ command: any ParsableCommand
	) async throws -> [FXCodexWarning] {
		guard !(command is Self) else { return [] }
		guard !(command is PreferencesCommand.List) else { return [] }
		guard !(command is PreferencesCommand.Set) else { return [] }
		guard !(command is RenameApplicationCommand) else { return [] }
		guard !(command is UpdateCommand) else { return [] }
		guard !(command is UninstallCommand) else { return [] }

		@Dependency(\.fxCodexClient) var client: FXCodexClient
		guard let version = SemanticVersion(Self.version)
		else { throw ValidationError("fxcodex has an invalid embedded version.") }
		return try await client.applyAutomaticPreferences(
			version,
			currentExecutableURL(),
			!(try environmentSwitch(
				named: "FXCODEX_DISABLE_AUTO_UPDATE"
			)
			?? false)
		)
	}

	private static func execute(
		_ command: any ParsableCommand
	) async throws {
		var command: any ParsableCommand = command
		if var asyncCommand = command as? any AsyncParsableCommand {
			try await asyncCommand.run()
		} else {
			try command.run()
		}
	}
}

internal struct VersionCommand: ParsableCommand {
	internal static let configuration: CommandConfiguration = .init(
		commandName: "version",
		abstract: "Show the fxcodex version."
	)

	@Flag(
		inversion: .prefixedNo,
		exclusivity: .chooseLast,
		help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
	)
	internal var json: Bool?

	internal init() {}

	internal func run() throws {
		if machineOutputRequested(self.json) {
			try printMachineResponse(VersionOutput(version: AppCommand.version))
			return
		}

		Swift.print(AppCommand.version)
	}
}
