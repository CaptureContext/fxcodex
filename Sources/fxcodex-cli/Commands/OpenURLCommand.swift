import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand {
	internal struct OpenURLCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "open-url",
			abstract: "Deliver an app link to one workspace's Codex instance.",
			discussion: """
				Sends a link such as codex://… to the named workspace's Codex only. A running
				instance receives it as an Apple Event addressed to its process ID; otherwise
				that workspace's Codex launches with the link. The link never goes through
				Launch Services' scheme routing, so other workspaces never see it.

				The first delivery to a running instance can trigger macOS's Automation prompt
				for the app that runs fxcodex.

				Air Traffic Control in Arx can run it as a profile's script:
				  fxcodex open-url work "$1"
				"""
		)

		@Argument(help: "Workspace name, such as primary or work.")
		internal var workspaceName: String

		@Argument(help: "The link to deliver, such as codex://….")
		internal var url: String

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			let delivery: URLDelivery = try await client.openURL(self.url, self.workspaceName)

			if machineOutputRequested(self.json) {
				try printMachineResponse(OpenURLOutput(delivery))
				return
			}

			let reporter: TerminalReporter = await .init()
			switch delivery.method {
			case .appleEvent:
				await reporter.success("Sent the link to Codex · \(delivery.workspace.name) · pid \(delivery.processID).")
			case .launch:
				await reporter.success("Launched Codex · \(delivery.workspace.name) · pid \(delivery.processID) with the link.")
			}
		}
	}
}
