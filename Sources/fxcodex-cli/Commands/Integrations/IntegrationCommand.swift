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
			subcommands: [Raycast.self, Attributes.self],
			defaultSubcommand: nil
		)

		internal init() {}

		internal func run() async throws {
			guard !globalMachineOutputRequested() else {
				throw ValidationError("Choose attributes or raycast when using --json.")
			}

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			guard
				let area = try prompts.select(
					"Choose an integration area:",
					[
						.init(value: "attributes", label: "Attributes", hint: "Read or modify integration data"),
						.init(value: "raycast", label: "Raycast", hint: "Show Raycast integration status"),
					]
				)
			else { return }

			switch area {
			case "attributes":
				try await Attributes().run()
			case "raycast":
				try await Raycast.Status().run()
			default:
				throw ValidationError("Unsupported integration area.")
			}
		}
	}
}

extension AppCommand.IntegrationsCommand {
	internal struct Attributes: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			commandName: "attributes",
			abstract: "Read and modify integration-owned attributes.",
			subcommands: [Get.self, Set.self, Remove.self]
		)

		internal init() {}

		internal func run() async throws {
			guard !globalMachineOutputRequested() else {
				throw ValidationError("Choose get, set, or remove when using --json.")
			}

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			guard
				let operation = try prompts.select(
					"Choose an attribute operation:",
					[
						.init(value: "get", label: "Get", hint: "Read a value"),
						.init(value: "set", label: "Set", hint: "Create or replace a value"),
						.init(value: "remove", label: "Remove", hint: "Delete a value"),
					]
				)
			else { return }

			let reporter = await TerminalReporter()

			guard let integration = try Attributes.resolveIntegration(
				nil,
				json: false,
				prompts: prompts
			) else { return }

			let path = await reporter.ask("Attribute path (blank for root):")

			switch operation {
			case "get":
				try Attributes.printValue(try Attributes.attributes.get(integration, .init(path)))

			case "set":
				let rawValue = await reporter.ask("JSON value (plain text is stored as a string):")

				try Attributes.attributes.set(integration, .init(path), Attributes.decodeValue(rawValue))
				await reporter.success("Integration attributes updated.")

			case "remove":
				guard try prompts.confirm("Remove '\(integration).\(path)'?") == true else { return }

				try Attributes.attributes.remove(integration, .init(path))
				await reporter.success("Integration attribute removed.")

			default:
				throw ValidationError("Unsupported attribute operation.")
			}
		}
	}
}

extension AppCommand.IntegrationsCommand.Attributes {
	internal struct Get: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(abstract: "Read an integration attribute.")

		@Argument(help: "Integration identifier, for example raycast. Omit to choose interactively.")
		internal var integration: String?

		@Option(name: .long, help: "Attribute path. Omit to read the integration root.")
		internal var path: String = ""

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			let json = machineOutputRequested(self.json)

			guard let integration = try AppCommand.IntegrationsCommand.Attributes.resolveIntegration(
				self.integration,
				json: json,
				prompts: prompts
			) else { return }

			let value = try AppCommand.IntegrationsCommand.Attributes.attributes.get(integration, .init(self.path))

			if json {
				try printMachineResponse(value)
			} else {
				try AppCommand.IntegrationsCommand.Attributes.printValue(value)
			}
		}
	}

	internal struct Set: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(abstract: "Create or replace an integration attribute.")

		@Argument(help: "Integration identifier, for example raycast. Omit to choose interactively.")
		internal var integration: String?

		@Argument(help: "JSON value. Invalid JSON is stored as a string. Omit to enter interactively.")
		internal var value: String?

		@Option(name: .long, help: "Attribute path. Omit to replace the integration root.")
		internal var path: String = ""

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			let json = machineOutputRequested(self.json)

			guard let integration = try AppCommand.IntegrationsCommand.Attributes.resolveIntegration(
				self.integration,
				json: json,
				prompts: prompts
			) else { return }

			let rawValue: String
			if let value = self.value {
				rawValue = value
			} else if json {
				throw ValidationError("An attribute value is required when using --json.")
			} else if let value = try prompts.text(
				"JSON value (plain text is stored as a string):",
				"{\"key\": \"value\"}"
			) {
				rawValue = value
			} else { return }

			let value = AppCommand.IntegrationsCommand.Attributes.decodeValue(rawValue)
			try AppCommand.IntegrationsCommand.Attributes.attributes.set(integration, .init(self.path), value)

			if json {
				try printMachineResponse(value)

			} else {
				let reporter = await TerminalReporter()
				await reporter.success("Integration attributes updated.")
			}
		}
	}

	internal struct Remove: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(abstract: "Remove an integration attribute.")

		@Argument(help: "Integration identifier, for example raycast. Omit to choose interactively.")
		internal var integration: String?

		@Option(name: .long, help: "Attribute path. Omit to remove the integration root.")
		internal var path: String = ""

		@Flag(
			inversion: .prefixedNo,
			exclusivity: .chooseLast,
			help: "Print a versioned machine-readable JSON response. Defaults from FXCODEX_JSON."
		)
		internal var json: Bool?

		internal init() {}

		internal func run() async throws {
			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			let json = machineOutputRequested(self.json)

			guard let integration = try AppCommand.IntegrationsCommand.Attributes.resolveIntegration(
				self.integration,
				json: json,
				prompts: prompts
			) else { return }

			try AppCommand.IntegrationsCommand.Attributes.attributes.remove(integration, .init(self.path))

			if json {
				try printMachineResponse(AttributeRemovalOutput(integration: integration, path: self.path))

			} else {
				let reporter = await TerminalReporter()
				await reporter.success("Integration attribute removed.")
			}
		}
	}

	fileprivate static var attributes: IntegrationAttributes {
		@Dependency(\.fxCodexClient)
		var client: FXCodexClient

		return client.integrations.attributes
	}

	fileprivate static func resolveIntegration(
		_ provided: String?,
		json: Bool,
		prompts: TerminalPromptsClient
	) throws -> String? {
		if let provided { return provided }

		guard !json else {
			throw ValidationError("An integration identifier is required when using --json.")
		}

		let registeredIdentifiers = ["raycast"]
		let identifiers = (try Self.attributes.list() + registeredIdentifiers)
			.uniqued()
			.sorted()

		let manualValue = "__fxcodex_manual_integration__"
		let options = identifiers.map {
			TerminalPromptOption(value: $0, label: $0, hint: nil)
		} + [
			.init(value: manualValue, label: "Enter manually…", hint: "Use another integration identifier"),
		]

		guard let selected = try prompts.select("Select an integration:", options) else { return nil }

		if selected == manualValue {
			return try prompts.text("Integration identifier:", "raycast")
		}

		return selected
	}

	fileprivate static func decodeValue(_ rawValue: String) -> CodableValue {
		(try? JSONDecoder().decode(CodableValue.self, from: Data(rawValue.utf8))) ?? .string(rawValue)
	}

	fileprivate static func printValue(_ value: CodableValue) throws {
		let encoder = FXCodexJSONCoding.encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		guard let output = String(data: try encoder.encode(value), encoding: .utf8) else {
			throw CocoaError(.fileWriteInapplicableStringEncoding)
		}

		Swift.print(output)
	}
}

private struct AttributeRemovalOutput: Encodable {
	let integration: String
	let path: String
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
