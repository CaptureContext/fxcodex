import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Codex application controller")
struct CodexApplicationControllerTests {
	@Test("Renames a lone valid Codex bundle from ChatGPT to Codex")
	@MainActor
	func automaticRename() async throws {
		let fixture: ClientTestFixture = try .init()
		let chatGPTURL: URL = try fixture.makeApplication(named: "ChatGPT")
		let codexURL: URL = fixture.applicationsURL.appending(
			path: "Codex.app",
			directoryHint: .isDirectory
		)
		defer { fixture.remove() }

		let result: CodexApplicationRenameResult = try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let controller: CodexApplicationController = self.controller(for: fixture)
			return try controller.rename(to: .codex)
		}

		#expect(result == .init(
			outcome: .renamed,
			requestedName: .codex,
			applicationURL: codexURL.standardizedFileURL,
			otherApplicationURL: chatGPTURL.standardizedFileURL
		))
		#expect(!FileManager.default.fileExists(atPath: chatGPTURL.path))
		#expect(FileManager.default.fileExists(atPath: codexURL.path))
	}

	@Test("Refuses to rename an unrelated ChatGPT bundle")
	@MainActor
	func bundleValidation() async throws {
		let fixture: ClientTestFixture = try .init()
		let chatGPTURL: URL = try fixture.makeApplication(
			named: "ChatGPT",
			bundleIdentifier: "com.openai.chat"
		)
		defer { fixture.remove() }

		withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let controller: CodexApplicationController = self.controller(for: fixture)
			#expect(throws: FXCodexError.applicationBundleMismatch(chatGPTURL)) {
				try controller.rename(to: .codex)
			}
		}

		#expect(FileManager.default.fileExists(atPath: chatGPTURL.path))
	}

	@Test("Does not rename when both application names are present")
	@MainActor
	func conflictingApplications() async throws {
		let fixture: ClientTestFixture = try .init()
		let chatGPTURL: URL = try fixture.makeApplication(named: "ChatGPT")
		let codexURL: URL = try fixture.makeApplication(named: "Codex")
		defer { fixture.remove() }

		let output: (CodexApplicationRenameResult, URL?) = try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let controller: CodexApplicationController = self.controller(for: fixture)
			return (
				try controller.rename(to: .codex),
				controller.applicationURL()
			)
		}

		#expect(output.0.outcome == .conflict)
		#expect(output.0.applicationURL == codexURL.standardizedFileURL)
		#expect(output.0.otherApplicationURL == chatGPTURL.standardizedFileURL)
		#expect(output.1 == codexURL.standardizedFileURL)
		#expect(FileManager.default.fileExists(atPath: chatGPTURL.path))
		#expect(FileManager.default.fileExists(atPath: codexURL.path))
	}

	@Test("Undo restores the ChatGPT application name")
	@MainActor
	func undo() async throws {
		let fixture: ClientTestFixture = try .init()
		let codexURL: URL = try fixture.makeApplication(named: "Codex")
		let chatGPTURL: URL = fixture.applicationsURL.appending(
			path: "ChatGPT.app",
			directoryHint: .isDirectory
		)
		defer { fixture.remove() }

		let result: CodexApplicationRenameResult = try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let controller: CodexApplicationController = self.controller(for: fixture)
			return try controller.rename(to: .chatGPT)
		}

		#expect(result.outcome == .renamed)
		#expect(result.applicationURL == chatGPTURL.standardizedFileURL)
		#expect(!FileManager.default.fileExists(atPath: codexURL.path))
		#expect(FileManager.default.fileExists(atPath: chatGPTURL.path))
	}

	@Test("Ignores an unrelated bundle beside a valid Codex application")
	@MainActor
	func unrelatedAlternative() async throws {
		let fixture: ClientTestFixture = try .init()
		let chatGPTURL: URL = try fixture.makeApplication(
			named: "ChatGPT",
			bundleIdentifier: "com.openai.chat"
		)
		let codexURL: URL = try fixture.makeApplication(named: "Codex")
		defer { fixture.remove() }

		let result: CodexApplicationRenameResult = try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let controller: CodexApplicationController = self.controller(for: fixture)
			return try controller.rename(to: .codex)
		}

		#expect(result.outcome == .alreadyNamed)
		#expect(result.applicationURL == codexURL.standardizedFileURL)
		#expect(result.otherApplicationURL == nil)
		#expect(FileManager.default.fileExists(atPath: chatGPTURL.path))
	}

	@Test("Rename fails when neither application is present")
	@MainActor
	func missingApplications() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let controller: CodexApplicationController = self.controller(for: fixture)
			#expect(throws: FXCodexError.applicationNotFound) {
				try controller.rename(to: .codex)
			}
		}
	}

	@MainActor
	private func controller(
		for fixture: ClientTestFixture
	) -> CodexApplicationController {
		.init(
			applicationsDirectoryURL: fixture.applicationsURL,
			fileManager: .default,
			applicationURLsForBundleIdentifier: { _ in [] }
		)
	}
}
