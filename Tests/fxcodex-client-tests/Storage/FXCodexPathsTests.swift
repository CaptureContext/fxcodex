import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("fxcodex paths")
struct FXCodexPathsTests {
	@Test("Primary paths use standard Codex locations by default")
	func primaryDefaults() async throws {
		let fileManager: FileManager = .default
		let paths: FXCodexPaths = .create(
			fileManager: fileManager,
			environment: [:]
		)
		let applicationSupportURL: URL = try #require(fileManager.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first)

		#expect(paths.primaryCodexHomeURL == fileManager.homeDirectoryForCurrentUser.appending(
			path: ".codex",
			directoryHint: .isDirectory
		).standardizedFileURL)
		#expect(paths.primaryUserDataURL == applicationSupportURL.appending(
			path: "Codex",
			directoryHint: .isDirectory
		).standardizedFileURL)
	}

	@Test("Primary paths honor Codex environment overrides")
	func primaryEnvironmentOverrides() async throws {
		let paths: FXCodexPaths = .create(
			fileManager: .default,
			environment: [
				"CODEX_HOME": "/tmp/codex-home",
				"CODEX_ELECTRON_USER_DATA_PATH": "/tmp/codex-user-data",
			]
		)

		#expect(paths.primaryCodexHomeURL.path == "/tmp/codex-home")
		#expect(paths.primaryUserDataURL.path == "/tmp/codex-user-data")
	}
}
