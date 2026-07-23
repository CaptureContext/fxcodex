import ArgumentParser
import Testing
@testable
import FXCodexCLI

@Suite("Exec command")
struct ExecCommandTests {
	@Test("Forwards arguments")
	func forwardsArguments() async throws {
		let command: AppCommand.ExecCommand = try .parse([
			"primary",
			"--",
			"--full-auto",
		])
		#expect(command.workspaceName == "primary")
		#expect(forwardedArguments(from: command.arguments) == ["--full-auto"])
	}

	@Test("Accepts an empty argument list")
	func emptyArguments() async throws {
		let command: AppCommand.ExecCommand = try .parse([])
		#expect(command.workspaceName == nil)
		#expect(command.arguments.isEmpty)
	}
}
