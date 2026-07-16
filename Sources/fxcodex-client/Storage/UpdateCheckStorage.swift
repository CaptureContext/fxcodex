import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct UpdateCheckStorageClient: Sendable {
	var claimAutomaticCheck: @Sendable (Date, TimeInterval) throws -> Bool
}

extension DependencyValues {
	private enum UpdateCheckStorageClientKey: DependencyKey {
		static var liveValue: UpdateCheckStorageClient {
			let storage: UpdateCheckStorage = .init(fileManager: .default)
			return .init(
				claimAutomaticCheck: storage.claimAutomaticCheck
			)
		}
	}

	var _fxcodexUpdateChecks: UpdateCheckStorageClient {
		get { self[UpdateCheckStorageClientKey.self] }
		set { self[UpdateCheckStorageClientKey.self] = newValue }
	}
}

final class UpdateCheckStorage: @unchecked Sendable {
	private struct State: Codable {
		let lastAutomaticCheck: Date

		private enum CodingKeys: String, CodingKey {
			case lastAutomaticCheck = "last_automatic_check"
		}
	}

	private let decoder: JSONDecoder
	private let encoder: JSONEncoder
	private let fileManager: FileManager
	private let lock: NSLock

	@Dependency(\._fxcodexPaths)
	private var paths: FXCodexPaths

	init(fileManager: FileManager) {
		let decoder: JSONDecoder = .init()
		decoder.dateDecodingStrategy = .iso8601
		let encoder: JSONEncoder = FXCodexJSONCoding.encoder()
		encoder.dateEncodingStrategy = .iso8601
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		self.decoder = decoder
		self.encoder = encoder
		self.fileManager = fileManager
		self.lock = .init()
	}

	func claimAutomaticCheck(
		at date: Date,
		minimumInterval: TimeInterval
	) throws -> Bool {
		self.lock.lock()
		defer { self.lock.unlock() }

		if self.fileManager.fileExists(atPath: self.paths.updateStateURL.path) {
			let data: Data = try .init(contentsOf: self.paths.updateStateURL)
			let state: State = try self.decoder.decode(State.self, from: data)
			guard date.timeIntervalSince(state.lastAutomaticCheck) >= minimumInterval
			else { return false }
		}

		try self.fileManager.createDirectory(
			at: self.paths.rootURL,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		let data: Data = try self.encoder.encode(State(lastAutomaticCheck: date))
		try data.write(to: self.paths.updateStateURL, options: [.atomic])
		return true
	}
}
