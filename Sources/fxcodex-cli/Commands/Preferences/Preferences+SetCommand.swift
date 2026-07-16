import ArgumentParser
import Dependencies
import FXCodexClient

extension AppCommand.PreferencesCommand {
	internal struct Set: AsyncParsableCommand {
		internal static let configuration: CommandConfiguration = .init(
			abstract: "Set an fxcodex preference."
		)

		@Argument(help: "Preference name.")
		internal var preference: FXCodexPreference

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
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let preferences: FXCodexPreferences
			let valueDescription: String
			switch self.preference {
			case .autoRename:
				guard let value = self.value else {
					throw ValidationError("auto-rename requires a boolean value.")
				}
				guard self.updatePolicyOptions.isEmpty else {
					throw ValidationError("Automatic update options cannot be used with auto-rename.")
				}
				preferences = try await client.setAutoRename(value.value)
				valueDescription = value.value ? "enabled" : "disabled"

			case .autoUpdate:
				guard self.value == nil else {
					throw ValidationError("auto-update uses --patch-from, --minor-from, --major-from, --latest-from, or --disabled.")
				}
				let policy: AutoUpdatePolicy = try self.autoUpdatePolicy()
				preferences = try await client.setAutoUpdate(policy)
				valueDescription = policy.description
			}

			if machineOutputRequested(self.json) {
				try printMachineResponse(preferences)
				return
			}

			let reporter: TerminalReporter = await .init()
			await reporter.success(
				"Set '\(self.preference.rawValue)' to \(valueDescription)."
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
		guard self.updatePolicyOptions.count == 1,
			let policy = self.updatePolicyOptions.first
		else {
			throw ValidationError(
				"Choose exactly one of --patch-from, --minor-from, --major-from, --latest-from, or --disabled."
			)
		}
		return policy
	}
}
