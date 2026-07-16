import ArgumentParser
import Testing
@testable import FXCodexCLI

@Suite("CLI command")
struct CLICommandTests {
	@Test("Forwards arguments after the workspace")
	func forwardsArguments() async throws {
		let command: AppCommand.CLICommand = try .parse([
			"work",
			"--",
			"--model",
			"gpt-5",
		])
		#expect(command.workspaceName == "work")
		#expect(forwardedArguments(from: command.arguments) == ["--model", "gpt-5"])
	}

	@Test("Defaults to the current workspace")
	func currentWorkspace() async throws {
		let command: AppCommand.CLICommand = try .parse([])
		#expect(command.workspaceName == nil)
		#expect(command.arguments.isEmpty)
	}
}
