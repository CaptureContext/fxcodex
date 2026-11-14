import ArgumentParser
import Testing
@testable
import FXCodexCLI

@Suite("Open command")
struct OpenCommandTests {
	@Test("Accepts an explicit workspace")
	func explicitWorkspace() async throws {
		let command: AppCommand.OpenCommand = try .parse(["work"])
		#expect(command.workspaceName == "work")
	}

	@Test("Accepts an omitted workspace for interactive selection")
	func omittedWorkspace() async throws {
		let command: AppCommand.OpenCommand = try .parse([])
		#expect(command.workspaceName == nil)
	}
}

@Suite("Open URL command")
struct OpenURLCommandTests {
	@Test("Takes the workspace and the link as positional arguments")
	func arguments() async throws {
		let command: AppCommand.OpenURLCommand = try .parse(["work", "codex://login/callback?code=1"])
		#expect(command.workspaceName == "work")
		#expect(command.url == "codex://login/callback?code=1")
	}

	@Test("Requires both the workspace and the link")
	func missingArguments() async throws {
		#expect(throws: (any Error).self) {
			_ = try AppCommand.OpenURLCommand.parse(["work"])
		}
	}

	@Test("Is registered as a root subcommand")
	func registered() {
		#expect(AppCommand.configuration.subcommands.contains { $0 == AppCommand.OpenURLCommand.self })
	}
}
