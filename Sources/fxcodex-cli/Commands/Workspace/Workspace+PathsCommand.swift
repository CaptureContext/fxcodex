import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient

extension WorkspacePathComponent: ExpressibleByArgument {}

extension AppCommand.WorkspaceCommand {
	internal struct Paths: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Show the directories used by a Codex workspace."
		)

		@Argument(
			help: "Workspace name. Omit to choose interactively; JSON mode uses the current workspace."
		)
		internal var workspaceName: String?

		@Option(
			name: .long,
			help: "Stable lowercase workspace UUID. Cannot be combined with a workspace name."
		)
		internal var workspaceID: String?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Show every path. Enabled by default; defaults from FXCODEX_WORKSPACE_PATHS_ALL."
		)
		internal var all: Bool?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Show the fxcodex workspace root. Defaults from FXCODEX_WORKSPACE_PATHS_WORKSPACE_ROOT."
		)
		internal var workspaceRoot: Bool?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Show the Codex home. Defaults from FXCODEX_WORKSPACE_PATHS_CODEX_HOME."
		)
		internal var codexHome: Bool?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Show the desktop application user data. Defaults from FXCODEX_WORKSPACE_PATHS_USER_DATA."
		)
		internal var userData: Bool?

		@Option(
			name: .customLong("print"),
			help: "Print only one raw path without a label."
		)
		internal var printComponent: WorkspacePathComponent?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response without prompting. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			try self.validateOutputMode()

			let json: Bool = self.jsonOutputRequested()
			guard let workspace: Workspace = try await self.workspace(
				client: client,
				prompts: prompts,
				json: json
			) else { return }
			let paths: ResolvedWorkspacePaths = try .init(workspace: workspace)

			if let printComponent = self.printComponent {
				Swift.print(paths.url(for: printComponent).path)
				return
			}

			let sections: WorkspacePathSections = try self.sections()

			if json {
				try printMachineResponse(WorkspacePathsOutput(
					paths: paths,
					sections: sections
				))
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.info("Workspace: \(workspace.name)")
			if sections.workspaceRoot {
				await reporter.info("Workspace root: \(paths.workspaceRootURL.path)")
			}
			if sections.codexHome {
				await reporter.info("Codex home: \(paths.codexHomeURL.path)")
			}
			if sections.userData {
				await reporter.info("User data: \(paths.userDataURL.path)")
			}
		}
	}
}

extension AppCommand.WorkspaceCommand.Paths {
	internal func jsonOutputRequested(
		arguments: [String] = .init(CommandLine.arguments.dropFirst()),
		environment: [String: String]? = nil
	) -> Bool {
		guard self.printComponent == nil else { return false }
		return self.json
		?? globalMachineOutputRequested(
			arguments: arguments,
			environment: environment
		)
	}

	internal func sections(
		environment: [String: String]? = nil
	) throws -> WorkspacePathSections {
		let environment = environment ?? currentEnvironment()
		let environmentAll: Bool? = try environmentSwitch(
			named: "FXCODEX_WORKSPACE_PATHS_ALL",
			in: environment
		)
		let environmentWorkspaceRoot: Bool? = try environmentSwitch(
			named: "FXCODEX_WORKSPACE_PATHS_WORKSPACE_ROOT",
			in: environment
		)
		let environmentCodexHome: Bool? = try environmentSwitch(
			named: "FXCODEX_WORKSPACE_PATHS_CODEX_HOME",
			in: environment
		)
		let environmentUserData: Bool? = try environmentSwitch(
			named: "FXCODEX_WORKSPACE_PATHS_USER_DATA",
			in: environment
		)
		let all: Bool = self.all ?? environmentAll ?? true
		return .init(
			workspaceRoot: self.workspaceRoot
			?? environmentWorkspaceRoot
			?? all,
			codexHome: self.codexHome
			?? environmentCodexHome
			?? all,
			userData: self.userData
			?? environmentUserData
			?? all
		)
	}

	internal func validateOutputMode(
		arguments: [String] = .init(CommandLine.arguments.dropFirst())
	) throws {
		guard self.workspaceName == nil || self.workspaceID == nil else {
			throw ValidationError(
				"A workspace name and --workspace-id cannot be used together."
			)
		}

		let explicitJSON: Bool = self.json == true
		|| machineOutputArgumentValue(arguments: arguments) == true
		guard self.printComponent == nil || !explicitJSON else {
			throw ValidationError("--print and --json cannot be used together.")
		}
	}

	internal func workspace(
		client: FXCodexClient,
		prompts: TerminalPromptsClient,
		json: Bool
	) async throws -> Workspace? {
		if let workspaceID = self.workspaceID {
			guard let id = WorkspaceID(workspaceID)
			else { throw ValidationError("--workspace-id must be a lowercase UUID.") }

			let workspaces: [Workspace] = try await client.workspaces()
			guard let selected = workspaces.first(where: { $0.id == id })
			else { throw FXCodexError.workspaceNotFound(workspaceID) }

			return selected
		}

		if let workspaceName = self.workspaceName {
			let workspaces: [Workspace] = try await client.workspaces()
			guard let selected = workspaces.first(where: { $0.name == workspaceName })
			else { throw FXCodexError.workspaceNotFound(workspaceName) }

			return selected
		}

		let currentWorkspace: Workspace = try await client.currentWorkspace()
		guard !json else { return currentWorkspace }

		let workspaces: [Workspace] = try await client.workspaces()
		let orderedWorkspaces: [Workspace] = [currentWorkspace] + workspaces.filter { workspace in
			workspace.id != currentWorkspace.id
		}
		let options: [TerminalPromptOption] = orderedWorkspaces.map { workspace in
			.init(
				value: workspace.id.rawValue,
				label: workspace.name,
				hint: workspace.id == currentWorkspace.id ? "current" : nil
			)
		}

		guard let selectedWorkspaceID = try prompts.select(
			"Select a workspace to inspect:",
			options
		) else { return nil }

		guard
			let id = WorkspaceID(selectedWorkspaceID),
			let selected = orderedWorkspaces.first(where: { $0.id == id })
		else { throw FXCodexError.workspaceNotFound(selectedWorkspaceID) }

		return selected
	}
}
