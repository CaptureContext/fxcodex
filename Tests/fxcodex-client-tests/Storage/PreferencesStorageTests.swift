import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Preferences storage")
struct PreferencesStorageTests {
	@Test("Preferences default to disabled and persist using lower snake case")
	func persistence() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let storage: PreferencesStorage = .init(fileManager: .default)
			#expect(try storage.load() == .init(autoRename: false))
			try Data("{}".utf8).write(
				to: fixture.rootURL.appending(path: "preferences.json"),
				options: [.atomic]
			)
			#expect(try storage.load() == .init(autoRename: false))
			#expect(
				try storage.setAutoRename(true)
				== .init(autoRename: true)
			)
			let minimumVersion: SemanticVersion = .init(major: 1, minor: 5, patch: 0)
			#expect(
				try storage.setAutoUpdate(.minor(from: minimumVersion))
				== .init(
					autoRename: true,
					autoUpdate: .minor(from: minimumVersion)
				)
			)
			#expect(try storage.load() == .init(
				autoRename: true,
				autoUpdate: .minor(from: .init(major: 1, minor: 5, patch: 0))
			))

			let data: Data = try .init(contentsOf: fixture.rootURL.appending(
				path: "preferences.json"
			))
			let object: [String: Any] = try #require(
				JSONSerialization.jsonObject(with: data) as? [String: Any]
			)
			#expect(object["auto_rename"] as? Bool == true)
			let autoUpdate: [String: Any] = try #require(
				object["auto_update"] as? [String: Any]
			)
			#expect(autoUpdate["channel"] as? String == "minor")
			#expect(autoUpdate["from"] as? String == "1.5.0")
		}
	}
}
