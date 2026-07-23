import ArgumentParser
import Dependencies
import FXCodexClient
import Testing
@testable
import FXCodexCLI

@Suite("Uninstall command")
struct UninstallCommandTests {
	@Test("Root parses the uninstall command")
	func rootCommand() async throws {
		let command: any ParsableCommand = try AppCommand.parseAsRoot([
			"uninstall",
			"--leave-data",
			"--yes",
		])

		#expect(command is AppCommand.UninstallCommand)
	}

	@Test("Interactively selects data handling and confirms uninstall")
	func interactive() async throws {
		let disposition: LockIsolated<UninstallDataDisposition?> = .init(nil)
		let removedExecutable: LockIsolated<Bool> = .init(false)
		let options: LockIsolated<[TerminalPromptOption]> = .init([])
		var client: FXCodexClient = .init()
		client.uninstallData = { disposition.setValue($0) }

		try await withDependencies {
			$0.fxCodexClient = client
			$0._fxcodexTerminalPrompts = .init(
				select: { _, promptOptions in
					options.setValue(promptOptions)
					return UninstallDataDisposition.erase.rawValue
				},
				multiselect: { _, _ in nil },
				confirm: { _ in true }
			)
			$0._fxcodexSelfInstallation = .init(
				uninstall: { _ in
					removedExecutable.setValue(true)
					return .direct
				}
			)
		} operation: {
			let command: AppCommand.UninstallCommand = try .parse([])
			try await command.run()
		}

		#expect(options.value.map(\.value) == ["leave", "erase", "delete"])
		#expect(disposition.value == .erase)
		#expect(removedExecutable.value)
	}

	@Test("Explicit data handling and confirmation avoid prompts")
	func explicit() async throws {
		let disposition: LockIsolated<UninstallDataDisposition?> = .init(nil)
		let didPrompt: LockIsolated<Bool> = .init(false)
		var client: FXCodexClient = .init()
		client.uninstallData = { disposition.setValue($0) }

		try await withDependencies {
			$0.fxCodexClient = client
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in
					didPrompt.setValue(true)
					return nil
				},
				multiselect: { _, _ in nil },
				confirm: { _ in
					didPrompt.setValue(true)
					return nil
				}
			)
			$0._fxcodexSelfInstallation = .init(
				uninstall: { _ in .direct }
			)
		} operation: {
			let command: AppCommand.UninstallCommand = try .parse([
				"--delete-data",
				"--yes",
			])
			try await command.run()
		}

		#expect(!didPrompt.value)
		#expect(disposition.value == .delete)
	}
}
