import Dependencies
import Foundation
import Testing
@_spi(Internals) @testable import FXCodexClient

@Suite("Preferences client")
struct PreferencesClientTests {
	@Test("Preference changes control automatic application renaming")
	func automaticApplicationRename() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient

			let initialPreferences: FXCodexPreferences = try await client.preferences()
			#expect(initialPreferences == .init(autoRename: false))
			let initialWarnings: [FXCodexWarning] = try await client.applyAutomaticPreferences(
				.init(major: 0, minor: 1, patch: 0),
				fixture.executableURL,
				true
			)
			#expect(initialWarnings.isEmpty)
			#expect(await application.snapshot().applicationRenameRequestCount == 0)

			let updatedPreferences: FXCodexPreferences = try await client.setAutoRename(true)
			#expect(updatedPreferences == .init(autoRename: true))
			let updatedWarnings: [FXCodexWarning] = try await client.applyAutomaticPreferences(
				.init(major: 0, minor: 1, patch: 0),
				fixture.executableURL,
				true
			)
			#expect(updatedWarnings.isEmpty)
			#expect(await application.snapshot().applicationRenameRequestCount == 1)
			#expect(await application.snapshot().requestedApplicationNames == [.codex])
		}
	}

	@Test("Automatic rename reports conflicts as warnings")
	func automaticRenameConflict() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(renameOutcome: .conflict)
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			_ = try await client.setAutoRename(true)
			let warnings: [FXCodexWarning] = try await client.applyAutomaticPreferences(
				.init(major: 0, minor: 1, patch: 0),
				fixture.executableURL,
				true
			)

			#expect(warnings.map(\.code) == ["application_name_conflict"])
		}
	}

	@Test("Automatic rename failures become warnings when Codex is available")
	func automaticRenameFailureWithCodex() async throws {
		let fixture: ClientTestFixture = try .init()
		let codexURL: URL = URL(fileURLWithPath: "/Applications/Codex.app")
		let application: CodexApplicationSpy = .init(
			applicationURL: codexURL,
			renameError: .applicationBundleMismatch(
				URL(fileURLWithPath: "/Applications/ChatGPT.app")
			)
		)
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			_ = try await client.setAutoRename(true)
			let warnings: [FXCodexWarning] = try await client.applyAutomaticPreferences(
				.init(major: 0, minor: 1, patch: 0),
				fixture.executableURL,
				true
			)

			#expect(warnings.map(\.code) == ["automatic_rename_failed"])
		}
	}

	@Test("Automatic update applies the persisted policy at most when claimed")
	func automaticUpdate() async throws {
		let fixture: ClientTestFixture = try .init()
		let requests: LockIsolated<[(UpdateChannel, SemanticVersion?, URL)]> = .init([])
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = CodexApplicationSpy().client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
			$0._fxcodexUpdateChecks = .init(
				claimAutomaticCheck: { _, _ in true }
			)
			$0._fxcodexUpdater = .init(
				update: { currentVersion, channel, minimumVersion, executableURL in
					requests.withValue {
						$0.append((channel, minimumVersion, executableURL))
					}
					return .init(
						outcome: .alreadyCurrent,
						previousVersion: currentVersion,
						version: currentVersion
					)
				}
			)
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			let minimumVersion: SemanticVersion = .init(major: 0, minor: 9, patch: 0)
			_ = try await client.setAutoUpdate(.minor(from: minimumVersion))
			let warnings: [FXCodexWarning] = try await client.applyAutomaticPreferences(
				.init(major: 0, minor: 1, patch: 0),
				fixture.executableURL,
				true
			)

			#expect(warnings.isEmpty)
			#expect(requests.value.count == 1)
			#expect(requests.value[0].0 == .minor)
			#expect(requests.value[0].1 == minimumVersion)
			#expect(requests.value[0].2 == fixture.executableURL)

			_ = try await client.applyAutomaticPreferences(
				.init(major: 0, minor: 1, patch: 0),
				fixture.executableURL,
				false
			)
			#expect(requests.value.count == 1)
		}
	}

	@Test("Automatic update failures are non-fatal warnings")
	func automaticUpdateFailure() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = CodexApplicationSpy().client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
			$0._fxcodexUpdateChecks = .init(
				claimAutomaticCheck: { _, _ in true }
			)
			$0._fxcodexUpdater = .init(
				update: { _, _, _, _ in
					throw FXCodexError.updateRequestFailed(503)
				}
			)
		} operation: {
			@Dependency(\.fxCodexClient) var client: FXCodexClient
			_ = try await client.setAutoUpdate(.latest(from: .init(
				major: 0,
				minor: 1,
				patch: 0
			)))
			let warnings: [FXCodexWarning] = try await client.applyAutomaticPreferences(
				.init(major: 0, minor: 1, patch: 0),
				fixture.executableURL,
				true
			)

			#expect(warnings.map(\.code) == ["automatic_update_failed"])
		}
	}
}
