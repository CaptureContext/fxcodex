import ArgumentParser
import Testing
@testable
import FXCodexCLI

@Suite("App command")
struct AppCommandTests {
	@Test("Parses a workspace subcommand from the root")
	func workspaceSubcommand() async throws {
		let command: any ParsableCommand = try AppCommand.parseAsRoot([
			"workspace",
			"create",
			"work",
			"--use",
			"--open",
		])
		let create: AppCommand.WorkspaceCommand.Create = try #require(
			command as? AppCommand.WorkspaceCommand.Create
		)
		#expect(create.name == "work")
		#expect(create.use)
		#expect(create.open)
	}

	@Test("Parses a nested workspace open command from the root")
	func workspaceOpenSubcommand() async throws {
		let command: any ParsableCommand = try AppCommand.parseAsRoot([
			"workspace",
			"open",
			"work",
		])
		let open: AppCommand.OpenCommand = try #require(
			command as? AppCommand.OpenCommand
		)
		#expect(open.workspaceName == "work")
	}

	@Test("Parses workspace command aliases from the root")
	func workspaceAliases() async throws {
		let use: any ParsableCommand = try AppCommand.parseAsRoot([
			"use",
			"work",
		])
		let delete: any ParsableCommand = try AppCommand.parseAsRoot([
			"delete",
			"work",
			"personal",
			"--yes",
		])
		let erase: any ParsableCommand = try AppCommand.parseAsRoot([
			"erase",
			"work",
			"personal",
			"--yes",
		])

		#expect(use is AppCommand.WorkspaceCommand.Use)
		#expect(delete is AppCommand.WorkspaceCommand.Delete)
		#expect(erase is AppCommand.WorkspaceCommand.Erase)
	}

	@Test("Accepts the machine output flag before a subcommand")
	func globalJSON() async throws {
		let command: any ParsableCommand = try AppCommand.parseAsRoot([
			"--json",
			"status",
		])

		#expect(command is AppCommand.StatusCommand)
	}

	@Test("Workspace resolves its default list with global machine output")
	func workspaceListJSON() async throws {
		let command: any ParsableCommand = try AppCommand.parseAsRoot([
			"workspace",
			"--json",
		])

		#expect(command is AppCommand.WorkspaceCommand.List)
	}
}
