import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand {
	internal struct ExecCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "exec",
			abstract: "Run codex exec in a workspace."
		)

		@Argument(help: "Workspace name. Defaults to the current workspace.")
		internal var workspaceName: String?

		@Argument(
			parsing: .captureForPassthrough,
			help: "Arguments forwarded to codex exec."
		)
		internal var arguments: [String] = []

		internal init() {}

		internal func run() async throws {
			try rejectMachineOutput(for: "exec")

			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let invocation: CommandInvocation = try await client.codexInvocation(
				self.workspaceName,
				["exec"] + forwardedArguments(from: self.arguments)
			)
			try replaceProcess(with: invocation)
		}
	}
}
