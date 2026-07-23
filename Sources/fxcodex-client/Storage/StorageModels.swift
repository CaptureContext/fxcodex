import Foundation

struct StorageConfiguration: Codable, Equatable, Sendable {
	var schemaVersion: SchemaVersion
	var currentWorkspaceID: WorkspaceID
	var integrations: [String: CodableValue]

	init(
		schemaVersion: SchemaVersion = .v2_0,
		currentWorkspaceID: WorkspaceID,
		integrations: [String: CodableValue] = [:]
	) {
		self.schemaVersion = schemaVersion
		self.currentWorkspaceID = currentWorkspaceID
		self.integrations = integrations
	}

	private enum CodingKeys: String, CodingKey {
		case schemaVersion = "schema_version"
		case currentWorkspaceID = "current_workspace_id"
		case integrations
	}
}

struct WorkspaceConfiguration: Codable, Equatable, Sendable {
	var schemaVersion: SchemaVersion
	let id: WorkspaceID
	var name: String
	let kind: WorkspaceKind

	init(
		schemaVersion: SchemaVersion = .v2_0,
		id: WorkspaceID,
		name: String,
		kind: WorkspaceKind
	) {
		self.schemaVersion = schemaVersion
		self.id = id
		self.name = name
		self.kind = kind
	}

	private enum CodingKeys: String, CodingKey {
		case schemaVersion = "schema_version"
		case id
		case name
		case kind
	}
}

struct MigrationJournal: Codable, Equatable, Sendable {
	let sourceVersion: SchemaVersion
	let destinationVersion: SchemaVersion
	let primaryWorkspaceID: WorkspaceID
	let workspaceIDs: [String: WorkspaceID]

	private enum CodingKeys: String, CodingKey {
		case sourceVersion = "source_version"
		case destinationVersion = "destination_version"
		case primaryWorkspaceID = "primary_workspace_id"
		case workspaceIDs = "workspace_ids"
	}
}

struct RuntimeConfiguration: Codable, Equatable, Sendable {
	var schemaVersion: SchemaVersion
	var instances: [WorkspaceID: ApplicationInstanceRecord]

	init(
		schemaVersion: SchemaVersion = .v2_0,
		instances: [WorkspaceID: ApplicationInstanceRecord] = [:]
	) {
		self.schemaVersion = schemaVersion
		self.instances = instances
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.schemaVersion = try container.decode(SchemaVersion.self, forKey: .schemaVersion)
		let values = try container.decode([String: ApplicationInstanceRecord].self, forKey: .instances)
		self.instances = try Dictionary(uniqueKeysWithValues: values.map { key, value in
			guard let id = WorkspaceID(key) else {
				throw FXCodexError.invalidStorage("runtime instance key is not a lowercase UUID: \(key)")
			}
			return (id, value)
		})
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(self.schemaVersion, forKey: .schemaVersion)
		try container.encode(
			Dictionary(uniqueKeysWithValues: self.instances.map { ($0.key.rawValue, $0.value) }),
			forKey: .instances
		)
	}

	private enum CodingKeys: String, CodingKey {
		case schemaVersion = "schema_version"
		case instances
	}
}
