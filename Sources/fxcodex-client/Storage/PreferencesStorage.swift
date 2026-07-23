import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct PreferencesStorageClient: Sendable {
	var load: @Sendable () throws -> FXCodexPreferences
	var setAutoRename: @Sendable (Bool) throws -> FXCodexPreferences
	var setAutoUpdate: @Sendable (AutoUpdatePolicy) throws -> FXCodexPreferences
}

extension DependencyValues {
	private enum PreferencesStorageClientKey: DependencyKey {
		static var liveValue: PreferencesStorageClient {
			let storage: PreferencesStorage = .init(fileManager: .default)
			return .init(
				load: storage.load,
				setAutoRename: storage.setAutoRename,
				setAutoUpdate: storage.setAutoUpdate
			)
		}
	}

	var _fxcodexPreferences: PreferencesStorageClient {
		get { self[PreferencesStorageClientKey.self] }
		set { self[PreferencesStorageClientKey.self] = newValue }
	}
}

final class PreferencesStorage: @unchecked Sendable {
	private let decoder: JSONDecoder
	private let encoder: JSONEncoder
	private let fileManager: FileManager

	@Dependency(\._fxcodexPaths)
	private var paths: FXCodexPaths

	init(
		fileManager: FileManager
	) {
		let encoder: JSONEncoder = FXCodexJSONCoding.encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		self.decoder = .init()
		self.encoder = encoder
		self.fileManager = fileManager
	}

	func load() throws -> FXCodexPreferences {
		guard self.fileManager.fileExists(atPath: self.paths.preferencesURL.path) else { return .init() }

		let data: Data = try .init(contentsOf: self.paths.preferencesURL)
		return try self.decoder.decode(
			FXCodexPreferences.self,
			from: data
		)
	}

	func setAutoRename(_ value: Bool) throws -> FXCodexPreferences {
		var preferences: FXCodexPreferences = try self.load()
		preferences.autoRename = value
		try self.save(preferences)
		return preferences
	}

	func setAutoUpdate(_ value: AutoUpdatePolicy) throws -> FXCodexPreferences {
		var preferences: FXCodexPreferences = try self.load()
		preferences.autoUpdate = value
		try self.save(preferences)
		return preferences
	}
}


extension PreferencesStorage {
	private func save(_ preferences: FXCodexPreferences) throws {
		try self.fileManager.createDirectory(
			at: self.paths.rootURL,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		let data: Data = try self.encoder.encode(preferences)
		try data.write(
			to: self.paths.preferencesURL,
			options: [.atomic]
		)
	}
}
