import ArgumentParser

internal struct PreferenceValue: ExpressibleByArgument, Equatable {
	internal let value: Bool

	internal init?(
		argument: String
	) {
		switch argument.lowercased() {
		case "1", "true", "yes", "on", "enabled":
			self.value = true

		case "0", "false", "no", "off", "disabled":
			self.value = false

		default:
			return nil
		}
	}
}
