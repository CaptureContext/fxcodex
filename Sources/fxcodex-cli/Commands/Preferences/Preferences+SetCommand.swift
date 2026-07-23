import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.PreferencesCommand {
	internal struct Set: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Set an fxcodex preference."
		)

		@Argument(help: "Preference name. Omit to choose interactively.")
		internal var preference: FXCodexPreference?

		@Argument(help: "Boolean value for auto-rename: true, false, 1, 0, on, or off.")
		internal var value: PreferenceValue?

		@Option(help: "Automatically install patch updates starting from this version.")
		internal var patchFrom: SemanticVersion?

		@Option(help: "Automatically install minor updates starting from this version.")
		internal var minorFrom: SemanticVersion?

		@Option(help: "Automatically install stable updates starting from this version.")
		internal var majorFrom: SemanticVersion?

		@Option(help: "Automatically install the newest release, including prereleases, starting from this version.")
		internal var latestFrom: SemanticVersion?

		@Flag(help: "Disable automatic updates.")
		internal var disabled: Bool = false

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

			@Dependency(\._fxcodexTerminalPrompts)
			var prompts: TerminalPromptsClient

			let json = machineOutputRequested(self.json)

			let preference: FXCodexPreference

			if let provided = self.preference {
				preference = provided

			} else if json {
				throw ValidationError("A preference name is required when using --json.")

			} else {
				let options = FXCodexPreference.allCases.map {
					TerminalPromptOption(value: $0.rawValue, label: $0.rawValue, hint: nil)
				}

				guard
					let selected = try prompts.select("Select a preference:", options),
					let value = FXCodexPreference(rawValue: selected)
				else { return }

				preference = value
			}

			let preferences: FXCodexPreferences
			let valueDescription: String

			switch preference {
			case .autoRename:
				let enabled: Bool

				if let value = self.value {
					enabled = value.value
				} else if json {
					throw ValidationError("auto-rename requires a boolean value.")
				} else if let selected = try prompts.select(
					"Automatic application rename:",
					[
						.init(value: "true", label: "Enabled", hint: nil),
						.init(value: "false", label: "Disabled", hint: nil),
					]
				) {
					enabled = selected == "true"
				} else { return }

				guard self.updatePolicyOptions.isEmpty else {
					throw ValidationError("Automatic update options cannot be used with auto-rename.")
				}

				preferences = try await client.setAutoRename(enabled)
				valueDescription = enabled ? "enabled" : "disabled"

			case .autoUpdate:
				guard self.value == nil else {
					throw ValidationError("auto-update uses --patch-from, --minor-from, --major-from, --latest-from, or --disabled.")
				}

				let policy: AutoUpdatePolicy = try self.resolveAutoUpdatePolicy(
					json: json,
					prompts: prompts
				)
				preferences = try await client.setAutoUpdate(policy)
				valueDescription = policy.description
			}

			if json {
				try printMachineResponse(preferences)
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success(
				"Set '\(preference.rawValue)' to \(valueDescription)."
			)
		}
	}
}

extension FXCodexPreference: ExpressibleByArgument {}

extension SemanticVersion: ExpressibleByArgument {
	public init?(argument: String) {
		self.init(argument)
	}
}

extension AppCommand.PreferencesCommand.Set {
	private var updatePolicyOptions: [AutoUpdatePolicy] {
		var options: [AutoUpdatePolicy] = []

		if let patchFrom = self.patchFrom {
			options.append(.patch(from: patchFrom))
		}

		if let minorFrom = self.minorFrom {
			options.append(.minor(from: minorFrom))
		}

		if let majorFrom = self.majorFrom {
			options.append(.major(from: majorFrom))
		}

		if let latestFrom = self.latestFrom {
			options.append(.latest(from: latestFrom))
		}

		if self.disabled {
			options.append(.disabled)
		}

		return options
	}

	private func autoUpdatePolicy() throws -> AutoUpdatePolicy {
		guard
			self.updatePolicyOptions.count == 1,
			let policy = self.updatePolicyOptions.first
		else {
			throw ValidationError(
				"Choose exactly one of --patch-from, --minor-from, --major-from, --latest-from, or --disabled."
			)
		}

		return policy
	}

	private func resolveAutoUpdatePolicy(
		json: Bool,
		prompts: TerminalPromptsClient
	) throws -> AutoUpdatePolicy {
		if !self.updatePolicyOptions.isEmpty || json {
			return try self.autoUpdatePolicy()
		}

		guard
			let channel = try prompts.select(
				"Automatic update policy:",
				[
					.init(value: "disabled", label: "Disabled", hint: nil),
					.init(value: "patch", label: "Patch", hint: "Only patch releases"),
					.init(value: "minor", label: "Minor", hint: "Patch and minor releases"),
					.init(value: "major", label: "Stable", hint: "Any stable release"),
					.init(value: "latest", label: "Latest", hint: "Include prereleases"),
				]
			)
		else { throw CleanExit.message("Cancelled.") }

		guard channel != "disabled" else { return .disabled }

		guard
			let rawVersion = try prompts.text("Minimum version:", AppCommand.version),
			let version = SemanticVersion(rawVersion)
		else {
			throw ValidationError("The minimum version must use semantic version format.")
		}

		switch channel {
		case "patch": return .patch(from: version)
		case "minor": return .minor(from: version)
		case "major": return .major(from: version)
		case "latest": return .latest(from: version)
		default: throw ValidationError("Unsupported automatic update policy.")
		}
	}
}
