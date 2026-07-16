import ArgumentParser
import Testing
@testable import FXCodexCLI

@Suite("Open command")
struct OpenCommandTests {
	@Test("Accepts an explicit workspace")
	func explicitWorkspace() async throws {
		let command: AppCommand.OpenCommand = try .parse(["work"])
		#expect(command.workspaceName == "work")
	}

	@Test("Defaults to the current workspace")
	func currentWorkspace() async throws {
		let command: AppCommand.OpenCommand = try .parse([])
		#expect(command.workspaceName == nil)
	}
}
