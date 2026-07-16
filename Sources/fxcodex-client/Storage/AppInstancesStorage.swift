import Foundation
import Dependencies
import DependenciesMacros

struct ApplicationInstanceRecord: Codable, Equatable, Sendable {
	let bundleURL: URL
	let launchDate: Date
	let processID: Int32

	init(
		bundleURL: URL,
		launchDate: Date,
		processID: Int32
	) {
		self.bundleURL = bundleURL
		self.launchDate = launchDate
		self.processID = processID
	}

	private enum CodingKeys: String, CodingKey {
		case bundleURL = "bundle_url"
		case launchDate = "launch_date"
		case processID = "process_id"
	}
}

@DependencyClient
struct AppInstancesStorageClient {
	var list: @Sendable () throws -> [String: ApplicationInstanceRecord]
	var find: @Sendable (_ for: String) throws -> ApplicationInstanceRecord?
	var save: @Sendable (ApplicationInstanceRecord, _ for: String) throws -> Void
	var remove: @Sendable (_ for: String) throws -> Void
	var transfer: @Sendable (_ from: String, _ to: String) throws -> Void
	var replaceBundleURL: @Sendable (_ from: URL, _ to: URL) throws -> Void
}

extension DependencyValues {
	private enum AppInstancesStorageClientKey: DependencyKey {
		static var liveValue: AppInstancesStorageClient {
			let storage = AppInstancesStorage(fileManager: .default)
			return .init(
				list: storage.records,
				find: storage.record,
				save: storage.setRecord,
				remove: { try storage.setRecord(nil, forWorkspaceNamed: $0) },
				transfer: storage.renameRecord,
				replaceBundleURL: storage.replaceBundleURL
			)
		}
	}

	var _fxcodexAppInstances: AppInstancesStorageClient {
		get { self[AppInstancesStorageClientKey.self] }
		set { self[AppInstancesStorageClientKey.self] = newValue }
	}
}

final class AppInstancesStorage: @unchecked Sendable {
	private let decoder: JSONDecoder
	private let encoder: JSONEncoder
	private let fileManager: FileManager

	@Dependency(\._fxcodexPaths)
	private var paths: FXCodexPaths

	init(
		fileManager: FileManager = .default
	) {
		let encoder: JSONEncoder = FXCodexJSONCoding.encoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		let decoder: JSONDecoder = .init()
		decoder.dateDecodingStrategy = .iso8601

		self.decoder = decoder
		self.encoder = encoder
		self.fileManager = fileManager
	}

	func records() throws -> [String: ApplicationInstanceRecord] {
		guard self.fileManager.fileExists(atPath: self.paths.instancesURL.path)
		else { return [:] }

		let data: Data = try .init(contentsOf: self.paths.instancesURL)
		return try self.decoder.decode(
			[String: ApplicationInstanceRecord].self,
			from: data
		)
	}

	func record(forWorkspaceNamed name: String) throws -> ApplicationInstanceRecord? {
		try self.records()[name]
	}

	func setRecord(
		_ record: ApplicationInstanceRecord?,
		forWorkspaceNamed name: String
	) throws {
		try self.fileManager.createDirectory(
			at: self.paths.rootURL,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)

		var records: [String: ApplicationInstanceRecord] = try self.records()
		records[name] = record
		let data: Data = try self.encoder.encode(records)
		try data.write(
			to: self.paths.instancesURL,
			options: [.atomic]
		)
	}

	func renameRecord(
		from oldName: String,
		to newName: String
	) throws {
		var records: [String: ApplicationInstanceRecord] = try self.records()
		records[newName] = records.removeValue(forKey: oldName)
		let data: Data = try self.encoder.encode(records)
		try data.write(
			to: self.paths.instancesURL,
			options: [.atomic]
		)
	}

	func replaceBundleURL(
		from oldURL: URL,
		to newURL: URL
	) throws {
		let oldURL: URL = oldURL.standardizedFileURL
		let newURL: URL = newURL.standardizedFileURL
		var records: [String: ApplicationInstanceRecord] = try self.records()

		for (workspaceName, record) in records where record.bundleURL.standardizedFileURL == oldURL {
			records[workspaceName] = .init(
				bundleURL: newURL,
				launchDate: record.launchDate,
				processID: record.processID
			)
		}

		guard !records.isEmpty else { return }
		let data: Data = try self.encoder.encode(records)
		try data.write(
			to: self.paths.instancesURL,
			options: [.atomic]
		)
	}
}
