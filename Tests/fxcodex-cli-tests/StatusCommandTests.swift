import ArgumentParser
import Foundation
import FXCodexClient
import Testing
@testable import FXCodexCLI

@Suite("Status command")
struct StatusCommandTests {
	@Test("Status sections are opt-in")
	func defaults() async throws {
		let command: AppCommand.StatusCommand = try .parse([])

		#expect(try command.sections(environment: [:]) == .init(
			preferences: false,
			workspaces: false,
			integrations: false
		))
	}

	@Test("All enables sections and scoped environment values can disable them")
	func environmentOverrides() async throws {
		let command: AppCommand.StatusCommand = try .parse([])
		let sections: StatusSections = try command.sections(environment: [
			"FXCODEX_STATUS_ALL": "1",
			"FXCODEX_STATUS_LIST_PREFERENCES": "-1",
		])

		#expect(sections == .init(
			preferences: false,
			workspaces: true,
			integrations: true
		))
	}

	@Test("Scoped CLI flags override all")
	func commandOverrides() async throws {
		let command: AppCommand.StatusCommand = try .parse([
			"--all",
			"--no-list-workspaces",
		])

		#expect(try command.sections(environment: [:]) == .init(
			preferences: true,
			workspaces: false,
			integrations: true
		))
	}

	@Test("Invalid environment switches are rejected")
	func invalidEnvironment() async throws {
		let command: AppCommand.StatusCommand = try .parse([])

		#expect(throws: ValidationError.self) {
			try command.sections(environment: [
				"FXCODEX_STATUS_ALL": "true",
			])
		}
	}

	@Test("Machine output omits unrequested sections")
	func machineOutputSections() async throws {
		let status: FXCodexStatus = .init(
			currentWorkspace: Workspace.primaryName,
			supportDirectoryURL: URL(fileURLWithPath: "/tmp/fxcodex"),
			applicationURL: nil,
			preferences: .init(autoRename: true),
			workspaces: [],
			raycastApplications: [],
			raycastScriptCommands: .init(
				directoryURL: nil,
				managedCommandCount: 0
			)
		)
		let data: Data = try encodedJSON(StatusOutput(
			status: status,
			sections: .init(
				preferences: true,
				workspaces: false,
				integrations: false
			)
		))
		let object: [String: Any] = try #require(
			JSONSerialization.jsonObject(with: data) as? [String: Any]
		)

		#expect(object["preferences"] != nil)
		#expect(object["workspaces"] == nil)
		#expect(object["raycastApplications"] == nil)
		#expect(object["raycastScriptCommands"] == nil)
	}
}
