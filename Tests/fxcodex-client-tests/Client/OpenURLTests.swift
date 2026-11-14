import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Open URL")
struct OpenURLTests {
	private let link: String = "codex://auth/callback?code=abc&state=xyz"

	@Test("A running workspace gets the link at its own process ID only")
	func runningInstance() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init()
		defer { fixture.remove() }

		try await self.withClient(fixture, application) { client in
			_ = try await client.createWorkspace("work")
			_ = try await client.createWorkspace("personal")
			await application.setProcessID(1_001, forWorkspaceNamed: Workspace.primaryName)
			await application.setProcessID(2_002, forWorkspaceNamed: "work")
			await application.setProcessID(3_003, forWorkspaceNamed: "personal")

			let delivery: URLDelivery = try await client.openURL(self.link, "work")

			#expect(delivery.workspace.name == "work")
			#expect(delivery.processID == 2_002)
			#expect(delivery.method == .appleEvent)
			#expect(delivery.url.absoluteString == self.link)
		}

		let snapshot: CodexApplicationSpy.Snapshot = await application.snapshot()
		#expect(snapshot.sentURLs == [.init(url: try #require(URL(string: self.link)), processID: 2_002)])
		#expect(snapshot.launchedURLs.isEmpty)
		#expect(snapshot.openedWorkspaceNames.isEmpty)
	}

	@Test("A stopped workspace launches with the link")
	func stoppedInstance() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(openedProcessID: 7_007)
		defer { fixture.remove() }

		try await self.withClient(fixture, application) { client in
			_ = try await client.createWorkspace("work")
			await application.setProcessID(1_001, forWorkspaceNamed: Workspace.primaryName)

			let delivery: URLDelivery = try await client.openURL(self.link, "work")

			#expect(delivery.processID == 7_007)
			#expect(delivery.method == .launch)
		}

		let snapshot: CodexApplicationSpy.Snapshot = await application.snapshot()
		#expect(snapshot.launchedURLs == [.init(workspaceName: "work", url: try #require(URL(string: self.link)))])
		#expect(snapshot.sentURLs.isEmpty)
	}

	@Test("Scheme matching ignores case and accepts every registered scheme")
	func registeredSchemes() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(processIDs: ["primary": 1_001])
		defer { fixture.remove() }

		try await self.withClient(fixture, application) { client in
			_ = try await client.openURL("CODEX://new", Workspace.primaryName)
			_ = try await client.openURL("codex://threads/1", Workspace.primaryName)
		}

		let snapshot: CodexApplicationSpy.Snapshot = await application.snapshot()
		#expect(snapshot.sentURLs.map(\.processID) == [1_001, 1_001])
	}

	@Test("An unknown workspace fails before anything is delivered")
	func unknownWorkspace() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(processIDs: ["primary": 1_001])
		defer { fixture.remove() }

		try await self.withClient(fixture, application) { client in
			await #expect(throws: FXCodexError.workspaceNotFound("work")) {
				_ = try await client.openURL(self.link, "work")
			}
		}

		let snapshot: CodexApplicationSpy.Snapshot = await application.snapshot()
		#expect(snapshot.sentURLs.isEmpty)
		#expect(snapshot.launchedURLs.isEmpty)
	}

	@Test("Links Codex does not handle are rejected")
	func unsupportedURL() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(processIDs: ["primary": 1_001])
		defer { fixture.remove() }

		try await self.withClient(fixture, application) { client in
			for rawURL in ["https://chatgpt.com/auth", "claude://login/callback", "not a url", ""] {
				await #expect(
					throws: FXCodexError.unsupportedURL(
						rawURL,
						supportedSchemes: ["codex"]
					)
				) {
					_ = try await client.openURL(rawURL, Workspace.primaryName)
				}
			}
		}

		let snapshot: CodexApplicationSpy.Snapshot = await application.snapshot()
		#expect(snapshot.sentURLs.isEmpty)
		#expect(snapshot.launchedURLs.isEmpty)
	}

	@Test("Delivery failures surface instead of launching another instance")
	func deliveryFailure() async throws {
		let fixture: ClientTestFixture = try .init()
		let failure: FXCodexError = .urlDeliveryFailed("blocked")
		let application: CodexApplicationSpy = .init(
			processIDs: ["primary": 1_001],
			sendError: failure
		)
		defer { fixture.remove() }

		try await self.withClient(fixture, application) { client in
			await #expect(throws: failure) {
				_ = try await client.openURL(self.link, Workspace.primaryName)
			}
		}

		let snapshot: CodexApplicationSpy.Snapshot = await application.snapshot()
		#expect(snapshot.launchedURLs.isEmpty)
	}

	@Test("A missing Codex installation is reported")
	func missingApplication() async throws {
		let fixture: ClientTestFixture = try .init()
		let application: CodexApplicationSpy = .init(urlSchemes: nil)
		defer { fixture.remove() }

		try await self.withClient(fixture, application) { client in
			await #expect(throws: FXCodexError.applicationNotFound) {
				_ = try await client.openURL(self.link, Workspace.primaryName)
			}
		}
	}

	private func withClient(
		_ fixture: ClientTestFixture,
		_ application: CodexApplicationSpy,
		operation: (FXCodexClient) async throws -> Void
	) async throws {
		try await withDependencies {
			$0.context = .live
			$0._fxcodexApplication = application.client
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
			$0._fxcodexRaycast = .fixture
		} operation: {
			@Dependency(\.fxCodexClient)
			var client: FXCodexClient

			try await operation(client)
		}
	}
}
