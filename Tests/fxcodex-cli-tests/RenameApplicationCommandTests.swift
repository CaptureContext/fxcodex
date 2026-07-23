import ArgumentParser
import Testing
@testable
import FXCodexCLI

@Suite("Rename application command")
struct RenameApplicationCommandTests {
	@Test("Root parses the rename command")
	func rootCommand() async throws {
		let command: any ParsableCommand = try AppCommand.parseAsRoot([
			"rename",
			"--undo",
		])
		let rename: AppCommand.RenameApplicationCommand = try #require(
			command as? AppCommand.RenameApplicationCommand
		)

		#expect(rename.undo)
	}

	@Test("Rename defaults to the Codex application name")
	func defaultDirection() async throws {
		let command: AppCommand.RenameApplicationCommand = try .parse([])

		#expect(!command.undo)
		#expect(command.json == nil)
	}
}
