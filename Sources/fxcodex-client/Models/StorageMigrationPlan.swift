public struct StorageMigration: Equatable, Sendable {
	public let sourceVersion: SchemaVersion
	public let destinationVersion: SchemaVersion
	public let steps: [String]
	public let requiresUserInput: Bool

	public init(
		sourceVersion: SchemaVersion,
		destinationVersion: SchemaVersion,
		steps: [String],
		requiresUserInput: Bool
	) {
		self.sourceVersion = sourceVersion
		self.destinationVersion = destinationVersion
		self.steps = steps
		self.requiresUserInput = requiresUserInput
	}
}

public struct StorageMigrationPlan: Equatable, Sendable {
	public let sourceVersion: SchemaVersion
	public let destinationVersion: SchemaVersion
	public let migrations: [StorageMigration]

	public var requiresUserInput: Bool {
		self.migrations.contains(where: \.requiresUserInput)
	}

	public init(
		sourceVersion: SchemaVersion,
		destinationVersion: SchemaVersion,
		migrations: [StorageMigration]
	) {
		self.sourceVersion = sourceVersion
		self.destinationVersion = destinationVersion
		self.migrations = migrations
	}
}
