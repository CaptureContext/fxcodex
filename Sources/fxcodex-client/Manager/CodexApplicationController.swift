import AppKit
import CoreServices
import Foundation
import Dependencies

@MainActor
public final class CodexApplicationController {
	public nonisolated static let bundleIdentifier: String = "com.openai.codex"

	private let applicationsDirectoryURL: URL
	private let applicationURLsForBundleIdentifier: (String) -> [URL]
	private let fileManager: FileManager

	@Dependency(\._fxcodexAppInstances)
	private var instances

	private let workspace: NSWorkspace

	public init(
		applicationsDirectoryURL: URL = URL(fileURLWithPath: "/Applications"),
		fileManager: FileManager = .default,
		workspace: NSWorkspace = .shared,
		applicationURLsForBundleIdentifier: ((String) -> [URL])? = nil
	) {
		self.applicationsDirectoryURL = applicationsDirectoryURL.standardizedFileURL
		self.applicationURLsForBundleIdentifier = applicationURLsForBundleIdentifier
			?? { workspace.urlsForApplications(withBundleIdentifier: $0) }
		self.fileManager = fileManager
		self.workspace = workspace
	}

	public func applicationURL() -> URL? {
		let discoveredURLs: [URL] = self.applicationURLsForBundleIdentifier(
			Self.bundleIdentifier
		)
		let knownURLs: [URL] = [
			self.codexApplicationURL,
			self.chatGPTApplicationURL,
		]

		let candidates: [URL] = (discoveredURLs + knownURLs)
		.reduce(into: [URL]()) { urls, url in
			let standardizedURL: URL = url.standardizedFileURL
			guard !urls.contains(standardizedURL) else { return }
			guard self.fileManager.fileExists(atPath: standardizedURL.path) else { return }
			guard Bundle(url: standardizedURL)?.bundleIdentifier == Self.bundleIdentifier else { return }
			urls.append(standardizedURL)
		}

		return candidates.sorted { lhs, rhs in
			self.applicationPriority(lhs) < self.applicationPriority(rhs)
		}.first
	}

	public func rename(
		to name: CodexApplicationName
	) throws -> CodexApplicationRenameResult {
		let applicationURL: URL = self.applicationURL(for: name)
		let otherApplicationURL: URL = self.applicationURL(for: name.alternative)
		let applicationExists: Bool = self.fileManager.fileExists(
			atPath: applicationURL.path
		)
		let otherApplicationExists: Bool = self.fileManager.fileExists(
			atPath: otherApplicationURL.path
		)
		let otherApplicationIsCodex: Bool = otherApplicationExists
			&& Bundle(url: otherApplicationURL)?.bundleIdentifier == Self.bundleIdentifier

		if applicationExists {
			try self.validateCodexBundle(at: applicationURL)
			return .init(
				outcome: otherApplicationIsCodex ? .conflict : .alreadyNamed,
				requestedName: name,
				applicationURL: applicationURL,
				otherApplicationURL: otherApplicationIsCodex ? otherApplicationURL : nil
			)
		}

		guard otherApplicationExists else { throw FXCodexError.applicationNotFound }
		try self.validateCodexBundle(at: otherApplicationURL)

		try self.fileManager.moveItem(
			at: otherApplicationURL,
			to: applicationURL
		)
		do {
			try self.instances.replaceBundleURL(
				otherApplicationURL,
				applicationURL
			)
		} catch {
			try? self.fileManager.moveItem(
				at: applicationURL,
				to: otherApplicationURL
			)
			throw error
		}
		return .init(
			outcome: .renamed,
			requestedName: name,
			applicationURL: applicationURL,
			otherApplicationURL: otherApplicationURL
		)
	}

	@discardableResult
	public func open(workspace: Workspace) async throws -> Int32 {
		if let application = try self.runningApplication(for: workspace) {
			application.unhide()
			application.activate(options: [.activateAllWindows])
			return application.processIdentifier
		}

		guard let applicationURL = self.applicationURL() else { throw FXCodexError.applicationNotFound }

		let application: NSRunningApplication = try await self.workspace.openApplication(
			at: applicationURL,
			configuration: self.launchConfiguration(for: workspace)
		)
		try self.cache(
			application: application,
			forWorkspaceID: workspace.id
		)

		return application.processIdentifier
	}

	/// URL schemes the installed Codex registers in `CFBundleURLTypes`, lowercased.
	///
	/// Web schemes are left out: they are not app links.
	public func urlSchemes() throws -> [String] {
		guard let applicationURL = self.applicationURL() else { throw FXCodexError.applicationNotFound }
		return Self.urlSchemes(ofApplicationAt: applicationURL)
	}

	/// Sends a `kAEGetURL` Apple Event to one process, the way Launch Services delivers a link,
	/// then brings that instance forward.
	public func send(
		url: URL,
		toProcessID processID: Int32
	) throws {
		let event: NSAppleEventDescriptor = Self.getURLEvent(
			url: url,
			processID: processID
		)

		let reply: NSAppleEventDescriptor
		do {
			reply = try event.sendEvent(
				options: [.waitForReply],
				timeout: Self.appleEventTimeout
			)
		} catch let error as NSError {
			throw FXCodexError.urlDeliveryFailed(
				Self.appleEventFailureMessage(code: error.code, processID: processID)
			)
		}

		// The app's handler can reject the event; that error comes back in the reply, not as a throw.
		if let code = Self.handlerErrorCode(in: reply) {
			throw FXCodexError.urlDeliveryFailed(
				Self.appleEventFailureMessage(code: code, processID: processID)
			)
		}

		if let application = NSRunningApplication(processIdentifier: processID) {
			application.unhide()
			application.activate(options: [.activateAllWindows])
		}
	}

	/// Launches a new instance of the workspace's Codex with the link, so it starts and
	/// receives the link in one call.
	public func launch(
		workspace: Workspace,
		with url: URL
	) async throws -> Int32 {
		guard let applicationURL = self.applicationURL() else { throw FXCodexError.applicationNotFound }

		let application: NSRunningApplication = try await self.workspace.open(
			[url],
			withApplicationAt: applicationURL,
			configuration: self.launchConfiguration(for: workspace)
		)
		try self.cache(
			application: application,
			forWorkspaceID: workspace.id
		)

		return application.processIdentifier
	}

	internal func launchConfiguration(
		for workspace: Workspace
	) throws -> NSWorkspace.OpenConfiguration {
		let configuration: NSWorkspace.OpenConfiguration = .init()
		configuration.activates = true
		configuration.createsNewApplicationInstance = true

		if workspace.kind == .managed {
			guard
				let codexHomeURL = workspace.codexHomeURL,
				let userDataURL = workspace.userDataURL
			else { throw FXCodexError.workspaceNotFound(workspace.name) }

			configuration.environment = [
				"CODEX_ELECTRON_USER_DATA_PATH": userDataURL.path,
				"CODEX_HOME": codexHomeURL.path,
			]
			configuration.arguments = [
				"--user-data-dir=\(userDataURL.path)",
			]
		}

		return configuration
	}

	public func runningProcessID(for workspace: Workspace) throws -> Int32? {
		try self.runningApplication(for: workspace)?.processIdentifier
	}

	public func removeRecord(forWorkspaceID id: WorkspaceID) throws {
		try self.instances.remove(for: id)
	}
}

@MainActor
	extension CodexApplicationController {
	private func runningApplication(for workspace: Workspace) throws -> NSRunningApplication? {
		let record = try self.instances.find(for: workspace.id)
		let application = record.flatMap { self.validatedApplication(for: $0) }
		if let application {
			return application
		}

		try self.instances.remove(for: workspace.id)

		guard workspace.kind == .primary else { return nil }
		let records: [WorkspaceID: ApplicationInstanceRecord] = try self.instances.list()
		let managedProcessIDs: Set<Int32> = .init(
			records
			.filter { $0.key != workspace.id }
			.compactMap { self.validatedApplication(for: $0.value)?.processIdentifier }
		)
		let candidates: [NSRunningApplication] = NSRunningApplication.runningApplications(
			withBundleIdentifier: Self.bundleIdentifier
		)
		.filter { application in
			!application.isTerminated
			&& !managedProcessIDs.contains(application.processIdentifier)
		}

		guard candidates.count <= 1 else {
			throw FXCodexError.ambiguousApplicationInstances(
				candidates.map(\.processIdentifier)
			)
		}
		guard let application = candidates.first else { return nil }

		try self.cache(
			application: application,
			forWorkspaceID: workspace.id
		)
		return application
	}

	private func validatedApplication(
		for record: ApplicationInstanceRecord
	) -> NSRunningApplication? {
		guard let application = NSRunningApplication(processIdentifier: record.processID) else { return nil }

		guard !application.isTerminated else { return nil }
		guard application.bundleIdentifier == Self.bundleIdentifier else { return nil }

		guard application.bundleURL?.standardizedFileURL == record.bundleURL.standardizedFileURL
		else { return nil }

		guard let launchDate = application.launchDate else { return nil }
		guard abs(launchDate.timeIntervalSince(record.launchDate)) < 1 else { return nil }

		return application
	}

	private func cache(
		application: NSRunningApplication,
		forWorkspaceID id: WorkspaceID
	) throws {
		guard
			let bundleURL = application.bundleURL,
			let launchDate = application.launchDate
		else { return }

		try self.instances.save(
			.init(
				bundleURL: bundleURL,
				launchDate: launchDate,
				processID: application.processIdentifier
			),
			for: id
		)
	}

	private func applicationPriority(_ url: URL) -> Int {
		switch url.lastPathComponent {
		case "Codex.app": 0
		case "ChatGPT.app": 1
		default: 2
		}
	}

	private func applicationURL(
		for name: CodexApplicationName
	) -> URL {
		self.applicationsDirectoryURL.appending(
			path: name.rawValue,
			directoryHint: .isDirectory
		)
	}

	private func validateCodexBundle(
		at url: URL
	) throws {
		guard Bundle(url: url)?.bundleIdentifier == Self.bundleIdentifier
		else { throw FXCodexError.applicationBundleMismatch(url) }
	}

	private var chatGPTApplicationURL: URL {
		self.applicationURL(for: .chatGPT)
	}

	private var codexApplicationURL: URL {
		self.applicationURL(for: .codex)
	}
}

extension CodexApplicationController {
	nonisolated static let appleEventTimeout: TimeInterval = 15

	nonisolated static let webURLSchemes: Set<String> = ["file", "http", "https"]

	nonisolated static func urlSchemes(
		ofApplicationAt applicationURL: URL
	) -> [String] {
		guard
			let bundle = Bundle(url: applicationURL),
			let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
		else { return [] }

		return types
		.flatMap { ($0["CFBundleURLSchemes"] as? [String]) ?? [] }
		.map { $0.lowercased() }
		.filter { !Self.webURLSchemes.contains($0) }
		.reduce(into: [String]()) { schemes, scheme in
			guard !schemes.contains(scheme) else { return }
			schemes.append(scheme)
		}
	}

	/// A GURL event addressed to one process ID, never to a bundle identifier,
	/// so no other instance of the same app can receive it.
	nonisolated static func getURLEvent(
		url: URL,
		processID: Int32
	) -> NSAppleEventDescriptor {
		let event: NSAppleEventDescriptor = .init(
			eventClass: AEEventClass(kInternetEventClass),
			eventID: AEEventID(kAEGetURL),
			targetDescriptor: NSAppleEventDescriptor(processIdentifier: processID),
			returnID: AEReturnID(kAutoGenerateReturnID),
			transactionID: AETransactionID(kAnyTransactionID)
		)
		event.setParam(
			NSAppleEventDescriptor(string: url.absoluteString),
			forKeyword: AEKeyword(keyDirectObject)
		)
		return event
	}

	/// The nonzero `keyErrorNumber` an Apple Event reply carries when the handler failed.
	nonisolated static func handlerErrorCode(
		in reply: NSAppleEventDescriptor
	) -> Int? {
		guard
			let descriptor = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)),
			descriptor.int32Value != 0
		else { return nil }

		return Int(descriptor.int32Value)
	}

	nonisolated static func appleEventFailureMessage(
		code: Int,
		processID: Int32
	) -> String {
		switch code {
		case Int(errAEEventNotPermitted):
			"macOS blocked Apple Events to Codex (pid \(processID)). Allow it in System Settings > Privacy & Security > Automation."

		case Int(procNotFound), Int(connectionInvalid):
			"Codex (pid \(processID)) is no longer running."

		case Int(errAEEventNotHandled):
			"Codex (pid \(processID)) did not accept the link."

		case Int(errAETimeout):
			"Codex (pid \(processID)) did not answer within \(Int(Self.appleEventTimeout)) seconds."

		default:
			"Apple Event to Codex (pid \(processID)) failed with OSStatus \(code)."
		}
	}
}
