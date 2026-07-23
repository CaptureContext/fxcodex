import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Update check storage")
struct UpdateCheckStorageTests {
	@Test("Claims automatic checks once per configured interval")
	func interval() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }
		let now: Date = .init(timeIntervalSince1970: 1_000_000)

		try withDependencies {
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let storage: UpdateCheckStorage = .init(fileManager: .default)
			let firstClaim: Bool = try storage.claimAutomaticCheck(
				at: now,
				minimumInterval: 100
			)
			let earlyClaim: Bool = try storage.claimAutomaticCheck(
				at: now.addingTimeInterval(99),
				minimumInterval: 100
			)
			let nextClaim: Bool = try storage.claimAutomaticCheck(
				at: now.addingTimeInterval(100),
				minimumInterval: 100
			)

			#expect(firstClaim)
			#expect(!earlyClaim)
			#expect(nextClaim)
			let data: Data = try .init(contentsOf: fixture.rootURL.appending(
				path: "update-state.json"
			))
			let object: [String: Any] = try #require(
				JSONSerialization.jsonObject(with: data) as? [String: Any]
			)
			#expect(Set(object.keys) == ["last_automatic_check"])
		}
	}
}
