import ArgumentParser
import Testing
@testable import FXCodexCLI

@Suite("Raycast command")
struct RaycastCommandTests {
	@Test("Install parses the Beta application component")
	func betaApplication() async throws {
		let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
			"app",
			"--beta",
		])
		#expect(command.component == .app)
		#expect(command.beta)
	}

	@Test("Install parses Script Command options")
	func scriptCommand() async throws {
		let command: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
			"script-command",
			"--directory",
			"/tmp/raycast",
			"--current-only",
			"--yes",
		])
		#expect(command.component == .scriptCommand)
		#expect(command.directory == "/tmp/raycast")
		#expect(command.currentOnly)
		#expect(command.yes)
	}

	@Test("Sync and uninstall require the Script Command component")
	func maintenanceCommands() async throws {
		let sync: AppCommand.IntegrationsCommand.Raycast.Sync = try .parse([
			"script-command",
		])
		let uninstall: AppCommand.IntegrationsCommand.Raycast.Uninstall = try .parse([
			"script-command",
			"--yes",
		])
		#expect(sync.component == .scriptCommand)
		#expect(uninstall.component == .scriptCommand)
		#expect(uninstall.yes)
	}
}
