import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand {
	internal struct OpenCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "open",
			abstract: "Open or focus a Codex workspace."
		)

		@Argument(help: "Workspace name. Omit to choose interactively; JSON mode uses the current workspace.")
		internal var workspaceName: String?

		@Option(name: .long, help: "Stable lowercase workspace UUID. Cannot be combined with a workspace name.")
		internal var workspaceID: String?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response without prompting. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			let json: Bool = machineOutputRequested(self.json)

			guard self.workspaceName == nil || self.workspaceID == nil else {
				throw ValidationError("A workspace name and --workspace-id cannot be used together.")
			}

			let workspace: Workspace

			if let workspaceID = self.workspaceID {
				guard let id = WorkspaceID(workspaceID) else {
					throw ValidationError("--workspace-id must be a lowercase UUID.")
				}

				guard let selected = try await client.workspaces().first(where: { $0.id == id }) else {
					throw FXCodexError.workspaceNotFound(workspaceID)
				}

				workspace = selected

			} else if let providedWorkspaceName = self.workspaceName {
				guard let selected = try await client.workspaces().first(where: { $0.name == providedWorkspaceName })
				else {
					throw FXCodexError.workspaceNotFound(providedWorkspaceName)
				}

				workspace = selected

			} else if json {
				workspace = try await client.currentWorkspace()

			} else {
				let currentWorkspace: Workspace = try await client.currentWorkspace()
				let workspaces: [Workspace] = try await client.workspaces()
				let orderedWorkspaces: [Workspace] = [currentWorkspace] + workspaces.filter { workspace in
					workspace.name != currentWorkspace.name
				}
				let options: [TerminalPromptOption] = orderedWorkspaces.map { workspace in
					.init(
						value: workspace.id.rawValue,
						label: workspace.name,
						hint: workspace.name == currentWorkspace.name ? "current" : nil
					)
				}

				guard let selectedWorkspaceID = try prompts.select(
					"Select a workspace to open:",
					options
				) else { return }

				guard
					let id = WorkspaceID(selectedWorkspaceID),
					let selected = orderedWorkspaces.first(where: { $0.id == id })
				else { throw FXCodexError.workspaceNotFound(selectedWorkspaceID) }

				workspace = selected
			}

			let processID: Int32 = try await client.openWorkspaceByID(workspace.id)

			if json {
				try printMachineResponse(OpenWorkspaceOutput(
					workspaceName: workspace.name,
					processID: processID
				))
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success("Codex is active · pid \(processID).")
		}
	}
}
