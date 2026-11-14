import AppKit
import CoreServices
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

	@Test("Managed launches carry the workspace's Codex home and profile; primary carries none")
	@MainActor
	func launchConfiguration() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }
		let codexHomeURL: URL = fixture.rootURL.appending(path: "work/codex-home", directoryHint: .isDirectory)
		let userDataURL: URL = fixture.rootURL.appending(path: "work/user-data", directoryHint: .isDirectory)
		let work: Workspace = .init(
			name: "work",
			kind: .managed,
			rootURL: fixture.rootURL,
			codexHomeURL: codexHomeURL,
			userDataURL: userDataURL
		)
		let primary: Workspace = .init(
			name: Workspace.primaryName,
			kind: .primary,
			rootURL: fixture.rootURL,
			codexHomeURL: nil,
			userDataURL: nil
		)
		let controller: CodexApplicationController = self.controller(for: fixture)
		let workConfiguration = try controller.launchConfiguration(for: work)
		let primaryConfiguration = try controller.launchConfiguration(for: primary)

		#expect(workConfiguration.createsNewApplicationInstance)
		#expect(workConfiguration.environment == [
			"CODEX_ELECTRON_USER_DATA_PATH": userDataURL.path,
			"CODEX_HOME": codexHomeURL.path,
		])
		#expect(workConfiguration.arguments == ["--user-data-dir=\(userDataURL.path)"])
		#expect(primaryConfiguration.createsNewApplicationInstance)
		#expect(primaryConfiguration.environment.isEmpty)
		#expect(primaryConfiguration.arguments.isEmpty)
	}

	@Test("Reads app link schemes from the installed bundle and drops web schemes")
	@MainActor
	func urlSchemes() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }
		_ = try fixture.makeApplication(
			named: "Codex",
			urlSchemes: [
				["codex", "http", "HTTPS", "Codex"],
			]
		)

		#expect(try self.controller(for: fixture).urlSchemes() == ["codex"])
	}

	@Test("Link schemes need an installed Codex")
	@MainActor
	func urlSchemesWithoutApplication() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }

		#expect(throws: FXCodexError.applicationNotFound) {
			try self.controller(for: fixture).urlSchemes()
		}
	}

	@Test("The GURL Apple Event is addressed to one process ID and carries the link")
	func getURLEvent() throws {
		let link: String = "codex://auth/callback?code=abc"
		let event: NSAppleEventDescriptor = CodexApplicationController.getURLEvent(
			url: try #require(URL(string: link)),
			processID: 4_321
		)
		let target: NSAppleEventDescriptor = try #require(
			event.attributeDescriptor(forKeyword: AEKeyword(keyAddressAttr))
		)
		let processID: Int32 = target.data.withUnsafeBytes { $0.load(as: Int32.self) }

		#expect(event.eventClass == AEEventClass(kInternetEventClass))
		#expect(event.eventID == AEEventID(kAEGetURL))
		#expect(target.descriptorType == DescType(typeKernelProcessID))
		#expect(processID == 4_321)
		#expect(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue == link)
	}

	@Test("Apple Event failures explain what to do")
	func appleEventFailureMessages() {
		let denied: String = CodexApplicationController.appleEventFailureMessage(
			code: Int(errAEEventNotPermitted),
			processID: 12
		)
		let gone: String = CodexApplicationController.appleEventFailureMessage(
			code: Int(procNotFound),
			processID: 12
		)
		let rejected: String = CodexApplicationController.appleEventFailureMessage(
			code: Int(errAEEventNotHandled),
			processID: 12
		)

		#expect(denied.contains("Privacy & Security > Automation"))
		#expect(gone == "Codex (pid 12) is no longer running.")
		#expect(rejected == "Codex (pid 12) did not accept the link.")
	}

	@Test("A handler error in the reply counts as a failed delivery")
	func replyHandlerError() {
		let success: NSAppleEventDescriptor = .appleEvent(
			withEventClass: AEEventClass(kCoreEventClass),
			eventID: AEEventID(kAEAnswer),
			targetDescriptor: nil,
			returnID: AEReturnID(kAutoGenerateReturnID),
			transactionID: AETransactionID(kAnyTransactionID)
		)
		let failure: NSAppleEventDescriptor = .appleEvent(
			withEventClass: AEEventClass(kCoreEventClass),
			eventID: AEEventID(kAEAnswer),
			targetDescriptor: nil,
			returnID: AEReturnID(kAutoGenerateReturnID),
			transactionID: AETransactionID(kAnyTransactionID)
		)
		failure.setParam(
			NSAppleEventDescriptor(int32: Int32(errAEEventNotHandled)),
			forKeyword: AEKeyword(keyErrorNumber)
		)

		#expect(CodexApplicationController.handlerErrorCode(in: success) == nil)
		#expect(CodexApplicationController.handlerErrorCode(in: failure) == Int(errAEEventNotHandled))
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
