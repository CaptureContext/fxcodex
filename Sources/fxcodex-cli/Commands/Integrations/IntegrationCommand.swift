import AppKit
import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient

extension AppCommand {
	internal struct IntegrationsCommand: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "integrations",
			abstract: "Manage integrations with other applications.",
			subcommands: [Raycast.self],
			defaultSubcommand: nil
		)

		internal init() {}
	}
}

extension AppCommand.IntegrationsCommand {
	internal struct Raycast: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "raycast",
			abstract: "Manage the Raycast integration.",
			subcommands: [
				Status.self,
				Install.self,
				Sync.self,
				Uninstall.self,
			],
			defaultSubcommand: Status.self
		)

		internal init() {}
	}
}
