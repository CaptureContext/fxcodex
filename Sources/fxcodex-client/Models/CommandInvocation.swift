public struct CommandInvocation: Equatable, Sendable {
	public let executable: String
	public let arguments: [String]
	public let environment: [String: String]

	public init(
		executable: String,
		arguments: [String],
		environment: [String: String]
	) {
		self.executable = executable
		self.arguments = arguments
		self.environment = environment
	}
}
