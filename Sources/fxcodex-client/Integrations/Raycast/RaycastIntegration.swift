import AppKit
import Dependencies
import Foundation

actor RaycastIntegration {
	@Dependency(\._fxcodexWorkspaces)
	private var workspaces

	@Dependency(\._fxcodexIntegrationAttributes)
	private var attributes

	init() {}

	func applicationStatus(for edition: RaycastEdition) async -> RaycastApplicationStatus {
		let applicationURL = await Self.applicationURL(for: edition)
		let version = applicationURL
			.flatMap(Bundle.init(url:))?
			.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
		return .init(edition: edition, applicationURL: applicationURL, version: version)
	}

	func applicationInstallation(for edition: RaycastEdition) async throws -> RaycastApplicationInstallation {
		if let applicationURL = await Self.applicationURL(for: edition) {
			return .alreadyInstalled(applicationURL)
		}

		switch edition {
		case .stable:
			return .command(.init(
				executable: "brew",
				arguments: ["install", "--cask", "raycast"],
				environment: [:]
			))

		case .beta:
			#if arch(arm64)
			guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
				throw FXCodexError.raycastBetaUnsupportedPlatform
			}
			guard let url = URL(string: "https://www.raycast.com/new") else {
				throw CocoaError(.fileNoSuchFile)
			}

			return .externalDownload(url)
			#else
			throw FXCodexError.raycastBetaUnsupportedPlatform
			#endif
		}
	}

	func installScriptCommands(
		at directoryURL: URL,
		fxcodexExecutableURL: URL,
		currentWorkspaceOnly: Bool
	) throws -> RaycastScriptCommandStatus {
		let workspaceIDs: Set<WorkspaceID>? = currentWorkspaceOnly
			? [try self.workspaces.currentWorkspace().id]
			: nil
		let configuration = RaycastScriptCommandConfiguration(
			directoryURL: directoryURL,
			fxcodexExecutableURL: fxcodexExecutableURL,
			workspaceIDs: workspaceIDs
		)

		try self.saveConfiguration(configuration)
		try self.reconcile(configuration)

		return try self.scriptCommandStatus()
	}

	func syncScriptCommands(fxcodexExecutableURL: URL) throws -> RaycastScriptCommandStatus {
		guard var configuration = try self.configuration() else {
			throw FXCodexError.raycastScriptCommandDirectoryMissing
		}

		configuration.fxcodexExecutableURL = fxcodexExecutableURL.standardizedFileURL
		try self.saveConfiguration(configuration)
		try self.reconcile(configuration)

		return try self.scriptCommandStatus()
	}

	func uninstallScriptCommands() throws -> RaycastScriptCommandStatus {
		if let configuration = try self.configuration() {
			try self.removeManagedCommands(in: configuration.generatedDirectoryURL)
		}

		do {
			try self.attributes.remove("raycast", try .init("script_commands"))
		} catch FXCodexError.integrationAttributeNotFound {
			// The generated files may still exist after a manually edited configuration.
		}

		return .init(directoryURL: nil, managedCommandCount: 0)
	}

	func scriptCommandStatus() throws -> RaycastScriptCommandStatus {
		guard let configuration = try self.configuration() else {
			return .init(directoryURL: nil, managedCommandCount: 0)
		}

		let count = try self.workspaces.list()
			.filter(configuration.includes)
			.reduce(into: 0) { count, workspace in
			let scriptCommandURL = self.scriptCommandURL(
				for: workspace,
				configuration: configuration
			)
			if try self.isManagedScriptCommand(at: scriptCommandURL) {
				count += 1
			}
		}

		return .init(directoryURL: configuration.directoryURL, managedCommandCount: count)
	}

	func workspaceCreated(_ workspace: Workspace) throws -> Workspace {
		try self.reconcileIfConfigured()
		return workspace
	}

	func workspaceDeleted(_ workspace: Workspace) throws {
		guard let configuration = try self.configuration() else { return }
		try self.removeManagedScriptCommand(at: self.scriptCommandURL(for: workspace, configuration: configuration))
	}

	func workspaceErased(_ workspace: Workspace) throws {
		try self.reconcileIfConfigured()
	}

	func workspaceRenamed(from oldWorkspace: Workspace, to newWorkspace: Workspace) throws -> Workspace {
		try self.reconcileIfConfigured()
		return newWorkspace
	}
}

private extension RaycastIntegration {
	static var scriptCommandMarker: String { "# fxcodex-managed-script-command" }

	@MainActor
	static func applicationURL(for edition: RaycastEdition) -> URL? {
		let bundleIdentifier: String
		let knownURL: URL
		switch edition {
		case .stable:
			bundleIdentifier = "com.raycast.macos"
			knownURL = URL(fileURLWithPath: "/Applications/Raycast.app")
		case .beta:
			bundleIdentifier = "com.raycast-x.macos"
			knownURL = URL(fileURLWithPath: "/Applications/Raycast Beta.app")
		}

		let discoveredURLs = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleIdentifier)
		return (discoveredURLs + [knownURL]).first { url in
			FileManager.default.fileExists(atPath: url.path)
				&& Bundle(url: url)?.bundleIdentifier == bundleIdentifier
		}
	}

	func configuration() throws -> RaycastScriptCommandConfiguration? {
		guard
			let value = try? self.attributes.get("raycast", .init("script_commands")),
			case let .dictionary(dictionary) = value,
			case let .string(path) = dictionary["path"],
			case let .string(executablePath) = dictionary["executable_path"]
		else { return nil }
		let workspaceIDs: Set<WorkspaceID>?

		if let value = dictionary["workspace_ids"] {
			guard case let .array(rawWorkspaceIDs) = value else { return nil }

			let parsedWorkspaceIDs = rawWorkspaceIDs.compactMap { value -> WorkspaceID? in
				guard case let .string(rawWorkspaceID) = value else { return nil }
				return WorkspaceID(rawWorkspaceID)
			}

			guard parsedWorkspaceIDs.count == rawWorkspaceIDs.count else { return nil }
			workspaceIDs = Set(parsedWorkspaceIDs)

		} else {
			workspaceIDs = nil
		}

		return .init(
			directoryURL: URL(filePath: path),
			fxcodexExecutableURL: URL(filePath: executablePath),
			workspaceIDs: workspaceIDs
		)
	}

	func saveConfiguration(_ configuration: RaycastScriptCommandConfiguration) throws {
		var value: [String: CodableValue] = [
			"path": .string(configuration.directoryURL.path),
			"executable_path": .string(configuration.fxcodexExecutableURL.path),
		]

		if let workspaceIDs = configuration.workspaceIDs {
			value["workspace_ids"] = .array(
				workspaceIDs.sorted().map { .string($0.rawValue) }
			)
		}

		try self.attributes.set(
			"raycast",
			.init("script_commands"),
			.dictionary(value)
		)
	}

	func reconcileIfConfigured() throws {
		guard let configuration = try self.configuration() else { return }
		try self.reconcile(configuration)
	}

	func reconcile(_ configuration: RaycastScriptCommandConfiguration) throws {
		try FileManager.default.createDirectory(
			at: configuration.generatedDirectoryURL,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o755]
		)

		let workspaces = try self.workspaces.list().filter(configuration.includes)
		let expectedURLs = Set(workspaces.map { self.scriptCommandURL(for: $0, configuration: configuration) })

		for url in try FileManager.default.contentsOfDirectory(
			at: configuration.generatedDirectoryURL,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) where url.pathExtension == "sh" && !expectedURLs.contains(url) {
			try self.removeManagedScriptCommand(at: url)
		}

		for workspace in workspaces {
			try self.writeScriptCommand(
				to: self.scriptCommandURL(for: workspace, configuration: configuration),
				workspace: workspace,
				fxcodexExecutableURL: configuration.fxcodexExecutableURL
			)
		}
	}

	func removeManagedCommands(in directoryURL: URL) throws {
		guard FileManager.default.fileExists(atPath: directoryURL.path) else { return }

		for url in try FileManager.default.contentsOfDirectory(
			at: directoryURL,
			includingPropertiesForKeys: [.isRegularFileKey],
			options: [.skipsHiddenFiles]
		) where url.pathExtension == "sh" {
			try self.removeManagedScriptCommand(at: url)
		}

		if try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).isEmpty {
			try FileManager.default.removeItem(at: directoryURL)
		}
	}

	func removeManagedScriptCommand(at url: URL) throws {
		guard try self.isManagedScriptCommand(at: url) else { return }

		try FileManager.default.removeItem(at: url)
		for iconURL in self.scriptCommandIconURLs(forScriptCommandAt: url) {
			if FileManager.default.fileExists(atPath: iconURL.path) {
				try FileManager.default.removeItem(at: iconURL)
			}
		}
	}

	func isManagedScriptCommand(at url: URL) throws -> Bool {
		guard FileManager.default.fileExists(atPath: url.path) else { return false }
		return try String(contentsOf: url, encoding: .utf8).contains(Self.scriptCommandMarker)
	}

	func scriptCommandURL(
		for workspace: Workspace,
		configuration: RaycastScriptCommandConfiguration
	) -> URL {
		configuration.generatedDirectoryURL.appending(
			path: "\(workspace.id.rawValue).sh",
			directoryHint: .notDirectory
		)
	}

	func writeScriptCommand(to url: URL, workspace: Workspace, fxcodexExecutableURL: URL) throws {
		let iconURLs = self.scriptCommandIconURLs(forScriptCommandAt: url)
		try RaycastScriptCommandIcon.light.write(to: iconURLs[0], options: .atomic)
		try RaycastScriptCommandIcon.dark.write(to: iconURLs[1], options: .atomic)
		let title = workspace.kind == .primary ? "Codex" : "Codex (\(workspace.name.capitalized))"
		let contents = """
		#!/bin/bash
		\(Self.scriptCommandMarker)

		# Required parameters:
		# @raycast.schemaVersion 1
		# @raycast.title \(title)
		# @raycast.mode silent

		# Optional parameters:
		# @raycast.packageName fxcodex
		# @raycast.icon ./\(iconURLs[0].lastPathComponent)
		# @raycast.iconDark ./\(iconURLs[1].lastPathComponent)
		# @raycast.description Open or focus the \(workspace.name) Codex workspace

		exec \(self.shellQuote(fxcodexExecutableURL.path)) open --workspace-id \(self.shellQuote(workspace.id.rawValue))
		"""
		try contents.write(to: url, atomically: true, encoding: .utf8)
		try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
	}

	func scriptCommandIconURLs(forScriptCommandAt url: URL) -> [URL] {
		let directoryURL = url.deletingLastPathComponent()
		let name = url.deletingPathExtension().lastPathComponent
		return [
			directoryURL.appending(path: "\(name)-light.png"),
			directoryURL.appending(path: "\(name)-dark.png"),
		]
	}

	func shellQuote(_ value: String) -> String {
		"'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
	}
}

private struct RaycastScriptCommandConfiguration: Equatable, Sendable {
	let directoryURL: URL
	var fxcodexExecutableURL: URL
	let workspaceIDs: Set<WorkspaceID>?

	init(
		directoryURL: URL,
		fxcodexExecutableURL: URL,
		workspaceIDs: Set<WorkspaceID>?
	) {
		self.directoryURL = directoryURL.standardizedFileURL
		self.fxcodexExecutableURL = fxcodexExecutableURL.standardizedFileURL
		self.workspaceIDs = workspaceIDs
	}

	var generatedDirectoryURL: URL {
		self.directoryURL.appending(path: "fxcodex", directoryHint: .isDirectory)
	}

	func includes(_ workspace: Workspace) -> Bool {
		self.workspaceIDs?.contains(workspace.id) ?? true
	}
}
