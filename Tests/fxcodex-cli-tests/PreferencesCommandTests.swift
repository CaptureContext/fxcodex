import ArgumentParser
import Dependencies
import FXCodexClient
import Testing
@testable
import FXCodexCLI

@Suite("Preferences command")
struct PreferencesCommandTests {
	@Test("Preferences defaults to list")
	func defaultList() async throws {
		let command: any ParsableCommand = try AppCommand.parseAsRoot([
			"preferences",
		])

		#expect(command is AppCommand.PreferencesCommand.List)
	}

	@Test("Set parses preference names and common boolean values")
	func set() async throws {
		let enabled: AppCommand.PreferencesCommand.Set = try .parse([
			"auto-rename",
			"on",
			"--json",
		])
		let disabled: AppCommand.PreferencesCommand.Set = try .parse([
			"auto-rename",
			"0",
		])

		#expect(enabled.preference == .autoRename)
		#expect(enabled.value?.value == true)
		#expect(enabled.json == true)
		#expect(disabled.preference == .autoRename)
		#expect(disabled.value?.value == false)

		let interactive: AppCommand.PreferencesCommand.Set = try .parse([])
		#expect(interactive.preference == nil)
		#expect(interactive.value == nil)
	}

	@Test("Auto-update parses every supported policy")
	func autoUpdate() async throws {
		let patch: AppCommand.PreferencesCommand.Set = try .parse([
			"auto-update",
			"--patch-from",
			"1.2.5",
		])
		let minor: AppCommand.PreferencesCommand.Set = try .parse([
			"auto-update",
			"--minor-from",
			"1.5.0",
		])
		let major: AppCommand.PreferencesCommand.Set = try .parse([
			"auto-update",
			"--major-from",
			"2.0.0",
		])
		let latest: AppCommand.PreferencesCommand.Set = try .parse([
			"auto-update",
			"--latest-from",
			"2.1.0",
		])
		let disabled: AppCommand.PreferencesCommand.Set = try .parse([
			"auto-update",
			"--disabled",
		])

		#expect(patch.patchFrom == .init(major: 1, minor: 2, patch: 5))
		#expect(minor.minorFrom == .init(major: 1, minor: 5, patch: 0))
		#expect(major.majorFrom == .init(major: 2, minor: 0, patch: 0))
		#expect(latest.latestFrom == .init(major: 2, minor: 1, patch: 0))
		#expect(disabled.disabled)
	}

	@Test("Automatic preferences run before normal commands but not preference commands")
	func executionPreparation() async throws {
		let requestCount: LockIsolated<Int> = .init(0)
		var client: FXCodexClient = .init()
		client.storageMigrationPlan = { nil }
		client.prepareStorage = {}
		client.applyAutomaticPreferences = { _, _, _ in
			requestCount.withValue { $0 += 1 }
			return []
		}

		try await withDependencies {
			$0.fxCodexClient = client
		} operation: {
			_ = try await AppCommand.prepareForExecution(VersionCommand())
			_ = try await AppCommand.prepareForExecution(
				AppCommand.PreferencesCommand.List()
			)
			_ = try await AppCommand.prepareForExecution(
				AppCommand.PreferencesCommand.Set()
			)
			_ = try await AppCommand.prepareForExecution(
				AppCommand.RenameApplicationCommand()
			)
			_ = try await AppCommand.prepareForExecution(
				AppCommand.UpdateCommand()
			)
			_ = try await AppCommand.prepareForExecution(
				AppCommand.UninstallCommand()
			)
		}

		#expect(requestCount.value == 1)
	}
}
