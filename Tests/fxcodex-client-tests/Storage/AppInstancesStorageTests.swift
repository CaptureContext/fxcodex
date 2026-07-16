import Dependencies
import Foundation
import Testing
@_spi(Internals) @testable import FXCodexClient

@Suite("Application instances storage")
struct AppInstancesStorageTests {
	@Test("Application renaming updates cached bundle URLs")
	func replaceBundleURL() async throws {
		let fixture: ClientTestFixture = try .init()
		let oldURL: URL = fixture.applicationsURL.appending(path: "ChatGPT.app")
		let newURL: URL = fixture.applicationsURL.appending(path: "Codex.app")
		defer { fixture.remove() }

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let storage: AppInstancesStorage = .init(fileManager: .default)
			try storage.setRecord(
				.init(
					bundleURL: oldURL,
					launchDate: Date(timeIntervalSince1970: 1_000),
					processID: 42
				),
				forWorkspaceNamed: "work"
			)
			let data: Data = try .init(contentsOf: fixture.rootURL.appending(
				path: "instances.json"
			))
			let object: [String: Any] = try #require(
				JSONSerialization.jsonObject(with: data) as? [String: Any]
			)
			let record: [String: Any] = try #require(object["work"] as? [String: Any])
			#expect(Set(record.keys) == ["bundle_url", "launch_date", "process_id"])
			try storage.replaceBundleURL(
				from: oldURL,
				to: newURL
			)

			#expect(
				try storage.record(forWorkspaceNamed: "work")?.bundleURL
				== newURL.standardizedFileURL
			)
		}
	}
}
