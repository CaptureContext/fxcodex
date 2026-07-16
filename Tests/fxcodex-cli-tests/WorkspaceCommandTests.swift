import ArgumentParser
import Testing
@testable import FXCodexCLI

@Suite("Workspace command")
struct WorkspaceCommandTests {
	@Test("Create parses lifecycle flags")
	func create() async throws {
		let command: AppCommand.WorkspaceCommand.Create = try .parse([
			"work",
			"--use",
			"--open",
			"--json",
		])
		#expect(command.name == "work")
		#expect(command.use)
		#expect(command.open)
		#expect(command.json == true)
	}

	@Test("Delete parses multiple workspaces and confirmation flag")
	func delete() async throws {
		let explicit: AppCommand.WorkspaceCommand.Delete = try .parse([
			"work",
			"personal",
			"--yes",
			"--json",
		])
		#expect(explicit.names == ["work", "personal"])
		#expect(explicit.yes)
		#expect(explicit.json == true)

		let interactive: AppCommand.WorkspaceCommand.Delete = try .parse([])
		#expect(interactive.names.isEmpty)
		#expect(!interactive.yes)
	}

	@Test("Erase parses multiple workspaces and confirmation flag")
	func erase() async throws {
		let explicit: AppCommand.WorkspaceCommand.Erase = try .parse([
			"work",
			"personal",
			"--yes",
			"--json",
		])
		#expect(explicit.names == ["work", "personal"])
		#expect(explicit.yes)
		#expect(explicit.json == true)

		let interactive: AppCommand.WorkspaceCommand.Erase = try .parse([])
		#expect(interactive.names.isEmpty)
		#expect(!interactive.yes)
	}

	@Test("Rename supports current and explicit forms")
	func rename() async throws {
		let current: AppCommand.WorkspaceCommand.Rename = try .parse(["new-name"])
		#expect(current.firstName == "new-name")
		#expect(current.secondName == nil)

		let explicit: AppCommand.WorkspaceCommand.Rename = try .parse([
			"old-name",
			"new-name",
		])
		#expect(explicit.firstName == "old-name")
		#expect(explicit.secondName == "new-name")
	}

	@Test("Use requires a workspace")
	func use() async throws {
		let command: AppCommand.WorkspaceCommand.Use = try .parse(["work"])
		#expect(command.name == "work")

		let interactive: AppCommand.WorkspaceCommand.Use = try .parse([])
		#expect(interactive.name == nil)
	}
}
