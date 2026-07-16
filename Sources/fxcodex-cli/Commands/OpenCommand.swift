import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand {
	internal struct OpenCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "open",
			abstract: "Open or focus a Codex workspace."
		)

		@Argument(help: "Workspace name. Defaults to the current workspace.")
		internal var workspaceName: String?

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response without prompting. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			@Dependency(\._fxcodexTerminalPrompts) var prompts: TerminalPromptsClient
			let json: Bool = machineOutputRequested(self.json)
			let workspaceName: String
			if let providedWorkspaceName = self.workspaceName {
				workspaceName = providedWorkspaceName
			} else if json {
				workspaceName = try await client.currentWorkspace().name
			} else {
				let currentWorkspace: Workspace = try await client.currentWorkspace()
				let workspaces: [Workspace] = try await client.workspaces()
				let orderedWorkspaces: [Workspace] = [currentWorkspace] + workspaces.filter { workspace in
					workspace.name != currentWorkspace.name
				}
				let options: [TerminalPromptOption] = orderedWorkspaces.map { workspace in
					.init(
						value: workspace.name,
						label: workspace.name,
						hint: workspace.name == currentWorkspace.name ? "current" : nil
					)
				}
				guard let selectedWorkspaceName = try prompts.select(
					"Select a workspace to open:",
					options
				) else { return }
				workspaceName = selectedWorkspaceName
			}

			let processID: Int32 = try await client.openWorkspace(workspaceName)
			if json {
				try printMachineResponse(OpenWorkspaceOutput(
					workspaceName: workspaceName,
					processID: processID
				))
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success("Codex is active · pid \(processID).")
		}
	}
}
