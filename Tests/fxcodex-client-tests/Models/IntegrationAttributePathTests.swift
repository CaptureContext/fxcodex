import Testing
@testable
import FXCodexClient

@Suite("Integration attribute paths")
struct IntegrationAttributePathTests {
	@Test("Parses members, keyed dictionaries, arrays, and functions")
	func components() throws {
		#expect(try IntegrationAttributePath("workspaces.[key: abc].items.[idx: 2].name").components == [
			.member("workspaces"),
			.key("abc"),
			.member("items"),
			.index(2),
			.member("name"),
		])
		#expect(try IntegrationAttributePath("workspaces.(keys).(first)").components == [
			.member("workspaces"),
			.function(.keys),
			.function(.first),
		])
		#expect(try IntegrationAttributePath("[key: \"a.b\"]").components == [.key("a.b")])
	}

	@Test("Rejects malformed paths")
	func invalid() {
		for path in [".", "workspaces..icon", "[idx: -1]", "(unknown)", "[key:]"] {
			#expect(throws: FXCodexError.invalidAttributePath(path)) {
				try IntegrationAttributePath(path)
			}
		}
	}
}
