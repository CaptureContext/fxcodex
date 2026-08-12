import Foundation
import Dependencies

public struct FXCodexPaths: Sendable {
	public let rootURL: URL
	public let primaryCodexHomeURL: URL
	public let primaryUserDataURL: URL
	public let configurationURL: URL
	public let instancesURL: URL
	public let migrationURL: URL
	public let preferencesURL: URL
	public let runtimeURL: URL
	public let storageLockURL: URL
	public let updateStateURL: URL
	public let workspacesURL: URL

	public init(rootURL: URL) {
		self.init(
			rootURL: rootURL,
			primaryCodexHomeURL: Self.primaryCodexHomeURL(
				fileManager: .default,
				environment: ProcessInfo.processInfo.environment
			),
			primaryUserDataURL: Self.primaryUserDataURL(
				fileManager: .default,
				environment: ProcessInfo.processInfo.environment
			)
		)
	}

	@_spi(Internals)
	public init(
		rootURL: URL,
		primaryCodexHomeURL: URL,
		primaryUserDataURL: URL
	) {
		self.rootURL = rootURL.standardizedFileURL
		self.primaryCodexHomeURL = primaryCodexHomeURL.standardizedFileURL
		self.primaryUserDataURL = primaryUserDataURL.standardizedFileURL
		self.configurationURL = self.rootURL.appending(
			path: "configuration.json",
			directoryHint: .notDirectory
		)
		self.instancesURL = self.rootURL.appending(
			path: "instances.json",
			directoryHint: .notDirectory
		)
		self.migrationURL = self.rootURL.appending(
			path: ".migration.json",
			directoryHint: .notDirectory
		)
		self.preferencesURL = self.rootURL.appending(
			path: "preferences.json",
			directoryHint: .notDirectory
		)
		self.runtimeURL = self.rootURL.appending(
			path: "runtime.json",
			directoryHint: .notDirectory
		)
		self.storageLockURL = self.rootURL.appending(
			path: "storage.lock",
			directoryHint: .notDirectory
		)
		self.updateStateURL = self.rootURL.appending(
			path: "update-state.json",
			directoryHint: .notDirectory
		)
		self.workspacesURL = self.rootURL.appending(
			path: "workspaces",
			directoryHint: .isDirectory
		)
	}

	public static func create(fileManager: FileManager = .default) -> Self {
		self.create(
			fileManager: fileManager,
			environment: ProcessInfo.processInfo.environment
		)
	}

	@_spi(Internals)
	public static func create(
		fileManager: FileManager,
		environment: [String: String]
	) -> Self {
		let applicationSupportURL: URL = self.applicationSupportURL(fileManager: fileManager)
		return Self(
			rootURL: applicationSupportURL.appending(
				path: "fxcodex",
				directoryHint: .isDirectory
			),
			primaryCodexHomeURL: self.primaryCodexHomeURL(
				fileManager: fileManager,
				environment: environment
			),
			primaryUserDataURL: self.primaryUserDataURL(
				fileManager: fileManager,
				environment: environment
			)
		)
	}
}

private extension FXCodexPaths {
	static func applicationSupportURL(fileManager: FileManager) -> URL {
		fileManager.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first
		?? fileManager.homeDirectoryForCurrentUser.appending(
			path: "Library/Application Support",
			directoryHint: .isDirectory
		)
	}

	static func primaryCodexHomeURL(
		fileManager: FileManager,
		environment: [String: String]
	) -> URL {
		self.environmentDirectoryURL(named: "CODEX_HOME", environment: environment)
		?? fileManager.homeDirectoryForCurrentUser.appending(
			path: ".codex",
			directoryHint: .isDirectory
		)
	}

	static func primaryUserDataURL(
		fileManager: FileManager,
		environment: [String: String]
	) -> URL {
		self.environmentDirectoryURL(
			named: "CODEX_ELECTRON_USER_DATA_PATH",
			environment: environment
		)
		?? self.applicationSupportURL(fileManager: fileManager).appending(
			path: "Codex",
			directoryHint: .isDirectory
		)
	}

	static func environmentDirectoryURL(
		named name: String,
		environment: [String: String]
	) -> URL? {
		guard let path = environment[name], !path.isEmpty else { return nil }
		return URL(
			filePath: NSString(string: path).expandingTildeInPath,
			directoryHint: .isDirectory
		).standardizedFileURL
	}
}

extension DependencyValues {
	private enum FXCodexPathsKey: DependencyKey {
		static var liveValue: FXCodexPaths { .create(fileManager: .default) }
	}

	@_spi(Internals)
	public var _fxcodexPaths: FXCodexPaths {

		get { self[FXCodexPathsKey.self] }
		set { self[FXCodexPathsKey.self] = newValue }
	}
}
