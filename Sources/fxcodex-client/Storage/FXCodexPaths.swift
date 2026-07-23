import Foundation
import Dependencies

public struct FXCodexPaths: Sendable {
	public let rootURL: URL
	public let configurationURL: URL
	public let instancesURL: URL
	public let migrationURL: URL
	public let preferencesURL: URL
	public let runtimeURL: URL
	public let storageLockURL: URL
	public let updateStateURL: URL
	public let workspacesURL: URL

	public init(rootURL: URL) {
		self.rootURL = rootURL.standardizedFileURL
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
		let applicationSupportURL: URL = fileManager.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first
		?? fileManager.homeDirectoryForCurrentUser.appending(
			path: "Library/Application Support",
			directoryHint: .isDirectory
		)

		return Self(rootURL: applicationSupportURL.appending(
			path: "fxcodex",
			directoryHint: .isDirectory
		))
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
