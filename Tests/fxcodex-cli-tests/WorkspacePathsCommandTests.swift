import ArgumentParser
import CustomDump
import Dependencies
import Foundation
import FXCodexClient
import Testing
@testable
import FXCodexCLI

@Suite("Workspace paths command")
struct WorkspacePathsCommandTests {
	@Test("Parses selectors, inclusion flags, raw output, and JSON")
	func parsing() async throws {
		let command: AppCommand.WorkspaceCommand.Paths = try .parse([
			"work",
			"--workspace-root",
			"--no-codex-home",
			"--user-data",
			"--print",
			"user-data",
		])

		#expect(command.workspaceName == "work")
		#expect(command.workspaceID == nil)
		#expect(command.workspaceRoot == true)
		#expect(command.codexHome == false)
		#expect(command.userData == true)
		#expect(command.printComponent == .userData)

		let byID: AppCommand.WorkspaceCommand.Paths = try .parse([
			"--workspace-id",
			"00000000-0000-0000-0000-000000000001",
			"--json",
		])
		#expect(byID.workspaceName == nil)
		#expect(byID.workspaceID == "00000000-0000-0000-0000-000000000001")
		#expect(byID.json == true)
	}

	@Test("Every path is included by default")
	func defaultSections() async throws {
		let command: AppCommand.WorkspaceCommand.Paths = try .parse([])

		expectNoDifference(
			try command.sections(environment: [:]),
			.init(
				workspaceRoot: true,
				codexHome: true,
				userData: true
			)
		)
	}

	@Test("Scoped environment values override all")
	func environmentSections() async throws {
		let command: AppCommand.WorkspaceCommand.Paths = try .parse([])

		expectNoDifference(
			try command.sections(environment: [
				"FXCODEX_WORKSPACE_PATHS_ALL": "-1",
				"FXCODEX_WORKSPACE_PATHS_CODEX_HOME": "1",
			]),
			.init(
				workspaceRoot: false,
				codexHome: true,
				userData: false
			)
		)
	}

	@Test("Scoped command flags override environment values")
	func commandSections() async throws {
		let command: AppCommand.WorkspaceCommand.Paths = try .parse([
			"--no-all",
			"--user-data",
		])

		expectNoDifference(
			try command.sections(environment: [
				"FXCODEX_WORKSPACE_PATHS_USER_DATA": "-1",
			]),
			.init(
				workspaceRoot: false,
				codexHome: false,
				userData: true
			)
		)
	}

	@Test("Invalid environment switches are rejected")
	func invalidEnvironment() async throws {
		let command: AppCommand.WorkspaceCommand.Paths = try .parse([])

		#expect(throws: ValidationError.self) {
			try command.sections(environment: [
				"FXCODEX_WORKSPACE_PATHS_CODEX_HOME": "true",
			])
		}
	}

	@Test("Raw and JSON output modes are mutually exclusive")
	func outputModeValidation() async throws {
		let command: AppCommand.WorkspaceCommand.Paths = try .parse([
			"work",
			"--print",
			"codex-home",
		])

		try command.validateOutputMode(arguments: [])
		#expect(!command.jsonOutputRequested(
			arguments: [],
			environment: ["FXCODEX_JSON": "1"]
		))
		#expect(throws: ValidationError.self) {
			try command.validateOutputMode(arguments: ["--json"])
		}

		let conflictingSelectors: AppCommand.WorkspaceCommand.Paths = try .parse([
			"work",
			"--workspace-id",
			"00000000-0000-0000-0000-000000000001",
		])
		#expect(throws: ValidationError.self) {
			try conflictingSelectors.validateOutputMode(arguments: [])
		}
	}

	@Test("Interactive selection presents the current workspace first")
	func interactiveSelection() async throws {
		let primary: Workspace = Self.workspace(
			named: Workspace.primaryName,
			kind: .primary,
			path: "/tmp/primary"
		)
		let work: Workspace = Self.workspace(
			named: "work",
			kind: .managed,
			path: "/tmp/work"
		)
		let options: LockIsolated<[TerminalPromptOption]> = .init([])
		var client: FXCodexClient = .init()
		client.currentWorkspace = { work }
		client.workspaces = { [primary, work] }
		let prompts: TerminalPromptsClient = .init(
			select: { _, promptOptions in
				options.setValue(promptOptions)
				return primary.id.rawValue
			},
			multiselect: { _, _ in nil },
			confirm: { _ in nil }
		)
		let command: AppCommand.WorkspaceCommand.Paths = try .parse([])

		let selected: Workspace? = try await command.workspace(
			client: client,
			prompts: prompts,
			json: false
		)

		#expect(selected?.id == primary.id)
		#expect(options.value.map(\.value) == [work.id.rawValue, primary.id.rawValue])
		#expect(options.value.map(\.hint) == ["current", nil])
	}

	@Test("JSON selection uses the current workspace without listing workspaces")
	func jsonSelection() async throws {
		let primary: Workspace = Self.workspace(
			named: Workspace.primaryName,
			kind: .primary,
			path: "/tmp/primary"
		)
		let didList: LockIsolated<Bool> = .init(false)
		var client: FXCodexClient = .init()
		client.currentWorkspace = { primary }
		client.workspaces = {
			didList.setValue(true)
			return []
		}
		let command: AppCommand.WorkspaceCommand.Paths = try .parse([])

		let selected: Workspace? = try await command.workspace(
			client: client,
			prompts: .init(
				select: { _, _ in nil },
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			),
			json: true
		)

		#expect(selected?.id == primary.id)
		#expect(!didList.value)
	}

	@Test("Machine output omits disabled paths")
	func machineOutputSections() async throws {
		let workspace: Workspace = Self.workspace(
			named: "work",
			kind: .managed,
			path: "/tmp/work"
		)
		let paths: ResolvedWorkspacePaths = try .init(workspace: workspace)
		let data: Data = try encodedJSON(WorkspacePathsOutput(
			paths: paths,
			sections: .init(
				workspaceRoot: true,
				codexHome: true,
				userData: false
			)
		))
		let object: [String: Any] = try #require(
			JSONSerialization.jsonObject(with: data) as? [String: Any]
		)

		#expect(object["workspace_id"] as? String == workspace.id.rawValue)
		#expect(object["workspace_name"] as? String == workspace.name)
		#expect(object["workspace_kind"] as? String == WorkspaceKind.managed.rawValue)
		#expect(object["workspace_root_url"] != nil)
		#expect(object["codex_home_url"] != nil)
		#expect(object["user_data_url"] == nil)
		#expect(paths.url(for: .codexHome).path == "/tmp/work/codex-home")
	}

	private static func workspace(
		named name: String,
		kind: WorkspaceKind,
		path: String
	) -> Workspace {
		let rootURL: URL = .init(filePath: path, directoryHint: .isDirectory)
		return .init(
			name: name,
			kind: kind,
			rootURL: rootURL,
			codexHomeURL: rootURL.appending(
				path: "codex-home",
				directoryHint: .isDirectory
			),
			userDataURL: rootURL.appending(
				path: "user-data",
				directoryHint: .isDirectory
			),
			integrations: [:]
		)
	}
}
