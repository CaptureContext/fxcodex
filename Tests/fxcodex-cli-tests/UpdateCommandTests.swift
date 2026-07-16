import ArgumentParser
import Testing
@testable import FXCodexCLI

@Suite("Update command")
struct UpdateCommandTests {
	@Test("Defaults to patch updates")
	func defaultChannel() async throws {
		let command: AppCommand.UpdateCommand = try .parse([])

		#expect(command.channel == .patch)
	}

	@Test("Parses minor, major, and latest channels exclusively")
	func channels() async throws {
		let minor: AppCommand.UpdateCommand = try .parse(["--minor"])
		let major: AppCommand.UpdateCommand = try .parse(["--major"])
		let latest: AppCommand.UpdateCommand = try .parse(["--latest", "--json"])

		#expect(minor.channel == .minor)
		#expect(major.channel == .major)
		#expect(latest.channel == .latest)
		#expect(latest.json == true)
		#expect(throws: Error.self) {
			try AppCommand.UpdateCommand.parse(["--minor", "--major"])
		}
	}

	@Test("Root parses the update command")
	func rootCommand() async throws {
		let command: any ParsableCommand = try AppCommand.parseAsRoot([
			"update",
			"--major",
		])

		#expect(command is AppCommand.UpdateCommand)
	}
}
