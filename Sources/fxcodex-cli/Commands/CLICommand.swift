import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand {
	internal struct CLICommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "cli",
			abstract: "Run Codex CLI in a workspace."
		)

		@Argument(help: "Workspace name. Defaults to the current workspace.")
		internal var workspaceName: String?

		@Argument(
			parsing: .captureForPassthrough,
			help: "Arguments forwarded to Codex."
		)
		internal var arguments: [String] = []

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "cli")

			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let invocation: CommandInvocation = try await client.codexInvocation(
				self.workspaceName,
				forwardedArguments(from: self.arguments)
			)
			try replaceProcess(with: invocation)
		}
	}
}
