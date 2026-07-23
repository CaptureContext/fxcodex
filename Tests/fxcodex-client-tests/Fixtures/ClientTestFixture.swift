import Foundation
@_spi(Internals)
@testable
import FXCodexClient

final class ClientTestFixture {
	let applicationURL: URL
	let applicationsURL: URL
	let executableURL: URL
	let rootURL: URL
	let scriptsURL: URL

	init() throws {
		let rootURL: URL = FileManager.default.temporaryDirectory.appending(
			path: "fxcodex-tests-\(UUID().uuidString)",
			directoryHint: .isDirectory
		)
		self.applicationURL = rootURL.appending(
			path: "fixtures/Codex.app",
			directoryHint: .isDirectory
		)
		self.applicationsURL = rootURL.appending(
			path: "fixtures/Applications",
			directoryHint: .isDirectory
		)
		self.executableURL = rootURL.appending(
			path: "fixtures/bin/fxcodex",
			directoryHint: .notDirectory
		)
		self.rootURL = rootURL
		self.scriptsURL = rootURL.appending(
			path: "raycast-scripts",
			directoryHint: .isDirectory
		)

		try FileManager.default.createDirectory(
			at: self.applicationURL,
			withIntermediateDirectories: true,
			attributes: nil
		)
		try self.createExecutable(at: self.executableURL)
	}

	func makeExecutable(named name: String) throws -> URL {
		let url: URL = self.executableURL
		.deletingLastPathComponent()
		.appending(path: name, directoryHint: .notDirectory)
		try self.createExecutable(at: url)
		return url
	}

	func makeApplication(
		named name: String,
		bundleIdentifier: String = CodexApplicationController.bundleIdentifier
	) throws -> URL {
		let applicationURL: URL = self.applicationsURL.appending(
			path: "\(name).app",
			directoryHint: .isDirectory
		)
		let contentsURL: URL = applicationURL.appending(
			path: "Contents",
			directoryHint: .isDirectory
		)
		try FileManager.default.createDirectory(
			at: contentsURL,
			withIntermediateDirectories: true,
			attributes: nil
		)
		let information: [String: Any] = [
			"CFBundleIdentifier": bundleIdentifier,
			"CFBundleName": name,
			"CFBundlePackageType": "APPL",
			"CFBundleVersion": "1",
		]
		let data: Data = try PropertyListSerialization.data(
			fromPropertyList: information,
			format: .xml,
			options: 0
		)
		try data.write(
			to: contentsURL.appending(path: "Info.plist"),
			options: [.atomic]
		)
		return applicationURL
	}

	func remove() {
		try? FileManager.default.removeItem(at: self.rootURL)
	}

	private func createExecutable(at url: URL) throws {
		try FileManager.default.createDirectory(
			at: url.deletingLastPathComponent(),
			withIntermediateDirectories: true,
			attributes: nil
		)
		try "#!/bin/sh\nexit 0\n".write(
			to: url,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o700],
			ofItemAtPath: url.path
		)
	}
}

actor CodexApplicationSpy {
	struct Snapshot: Equatable, Sendable {
		let applicationRenameRequestCount: Int
		let requestedApplicationNames: [CodexApplicationName]
		let openedWorkspaceNames: [String]
		let removedWorkspaceNames: [String]
		let renamedWorkspaces: [WorkspaceRename]
	}

	struct WorkspaceRename: Equatable, Sendable {
		let oldName: String
		let newName: String
	}

	private let applicationURLValue: URL?
	private let openedProcessID: Int32
	private let renameError: FXCodexError?
	private let renameOutcome: CodexApplicationRenameResult.Outcome
	private var applicationRenameRequestCount: Int = 0
	private var requestedApplicationNames: [CodexApplicationName] = []
	private var openedWorkspaceNames: [String] = []
	private var processIDs: [String: Int32]
	private var removedWorkspaceNames: [String] = []
	private var renamedWorkspaces: [WorkspaceRename] = []

	init(
		applicationURL: URL? = nil,
		openedProcessID: Int32 = 4_242,
		processIDs: [String: Int32] = [:],
		renameError: FXCodexError? = nil,
		renameOutcome: CodexApplicationRenameResult.Outcome = .alreadyNamed
	) {
		self.applicationURLValue = applicationURL
		self.openedProcessID = openedProcessID
		self.processIDs = processIDs
		self.renameError = renameError
		self.renameOutcome = renameOutcome
	}

	nonisolated var client: CodexApplicationClient {
		.init(
			applicationURL: { await self.applicationURL() },
			rename: { try await self.rename(to: $0) },
			open: { await self.open($0) },
			runningProcessID: { await self.runningProcessID(for: $0) },
			removeRecord: { await self.removeRecord(for: $0.name) }
		)
	}

	func setProcessID(
		_ processID: Int32?,
		forWorkspaceNamed name: String
	) {
		self.processIDs[name] = processID
	}

	func snapshot() -> Snapshot {
		.init(
			applicationRenameRequestCount: self.applicationRenameRequestCount,
			requestedApplicationNames: self.requestedApplicationNames,
			openedWorkspaceNames: self.openedWorkspaceNames,
			removedWorkspaceNames: self.removedWorkspaceNames,
			renamedWorkspaces: self.renamedWorkspaces
		)
	}

	private func applicationURL() -> URL? {
		self.applicationURLValue
	}

	private func rename(
		to name: CodexApplicationName
	) throws -> CodexApplicationRenameResult {
		self.applicationRenameRequestCount += 1
		self.requestedApplicationNames.append(name)
		if let renameError = self.renameError {
			throw renameError
		}
		return .init(
			outcome: self.renameOutcome,
			requestedName: name,
			applicationURL: self.applicationURLValue
			?? URL(fileURLWithPath: "/Applications/\(name.rawValue)"),
			otherApplicationURL: self.renameOutcome == .conflict
			? URL(fileURLWithPath: "/Applications/\(name.alternative.rawValue)")
			: nil
		)
	}

	private func open(_ workspace: Workspace) -> Int32 {
		self.openedWorkspaceNames.append(workspace.name)
		self.processIDs[workspace.name] = self.openedProcessID
		return self.openedProcessID
	}

	private func runningProcessID(for workspace: Workspace) -> Int32? {
		self.processIDs[workspace.name]
	}

	private func removeRecord(for name: String) {
		self.processIDs.removeValue(forKey: name)
		self.removedWorkspaceNames.append(name)
	}

}

extension Integrations.Raycast {
	static var fixture: Self {
		.init(
			applicationStatus: {
				.init(
					edition: $0,
					applicationURL: nil,
					version: nil
				)
			},
			applicationInstallation: {
				.command(.init(
					executable: "brew",
					arguments: ["install", "--cask", $0 == .beta ? "raycast-beta" : "raycast"],
					environment: [:]
				))
			},
			installScriptCommands: { directoryURL, _, _ in
				.init(
					directoryURL: directoryURL,
					managedCommandCount: 0
				)
			},
			syncScriptCommands: { _ in
				.init(
					directoryURL: nil,
					managedCommandCount: 0
				)
			},
			uninstallScriptCommands: {
				.init(
					directoryURL: nil,
					managedCommandCount: 0
				)
			},
			scriptCommandStatus: {
				.init(
					directoryURL: nil,
					managedCommandCount: 0
				)
			},
			workspaceCreated: { $0 },
			workspaceDeleted: { _ in },
			workspaceErased: { _ in },
			workspaceRenamed: { _, newWorkspace in newWorkspace }
		)
	}
}
