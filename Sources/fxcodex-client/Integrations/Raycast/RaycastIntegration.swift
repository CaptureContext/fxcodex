import AppKit
import CasePaths
import Dependencies
import Foundation

actor RaycastIntegration {
	@Dependency(\._fxcodexWorkspaces)
	private var workspaces

	init() {}

	func applicationStatus(
		for edition: RaycastEdition
	) async -> RaycastApplicationStatus {
		let applicationURL: URL? = await Self.applicationURL(for: edition)
		let version: String? = applicationURL
		.flatMap(Bundle.init(url:))?
		.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

		return .init(
			edition: edition,
			applicationURL: applicationURL,
			version: version
		)
	}

	func applicationInstallation(
		for edition: RaycastEdition
	) async throws -> RaycastApplicationInstallation {
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
			guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
			else { throw FXCodexError.raycastBetaUnsupportedPlatform }
			#else
			throw FXCodexError.raycastBetaUnsupportedPlatform
			#endif

			guard let url = URL(string: "https://www.raycast.com/new")
			else { throw CocoaError(.fileNoSuchFile) }
			return .externalDownload(url)
		}
	}

	func installScriptCommands(
		at directoryURL: URL,
		fxcodexExecutableURL: URL,
		includeCurrentWorkspace: Bool,
		includeAllWorkspaces: Bool
	) throws -> RaycastScriptCommandStatus {
		var selectedWorkspaces: [String: Workspace] = [:]

		if includeAllWorkspaces {
			for workspace in try self.workspaces.list() {
				selectedWorkspaces[workspace.name] = workspace
			}
		}

		if includeCurrentWorkspace {
			let workspace: Workspace = try self.workspaces.currentWorkspace()
			selectedWorkspaces[workspace.name] = workspace
		}

		for workspace in selectedWorkspaces.values.sorted(by: { $0.name < $1.name }) {
			_ = try self.installScriptCommand(
				for: workspace,
				at: directoryURL,
				fxcodexExecutableURL: fxcodexExecutableURL
			)
		}

		try self.setAutomaticManagement(
			includeAllWorkspaces
			? .init(
				directoryURL: directoryURL,
				fxcodexExecutableURL: fxcodexExecutableURL
			)
			: nil
		)
		return try self.scriptCommandStatus()
	}

	func syncScriptCommands(
		fxcodexExecutableURL: URL
	) throws -> RaycastScriptCommandStatus {
		let configuredWorkspaces: [Workspace] = try self.workspaces.list().filter { workspace in
			workspace.raycastScriptCommandConfiguration != nil
		}
		guard !configuredWorkspaces.isEmpty
		else { throw FXCodexError.raycastScriptCommandDirectoryMissing }

		for workspace in configuredWorkspaces {
			guard let configuration = workspace.raycastScriptCommandConfiguration
			else { continue }
			_ = try self.installScriptCommand(
				for: workspace,
				at: configuration.directoryURL,
				fxcodexExecutableURL: fxcodexExecutableURL
			)
		}

		let primaryWorkspace: Workspace = try self.workspaces.findWorkspace(named: Workspace.primaryName)
		if let automaticManagement = primaryWorkspace.raycastAutomaticManagement {
			try self.setAutomaticManagement(.init(
				directoryURL: automaticManagement.directoryURL,
				fxcodexExecutableURL: fxcodexExecutableURL
			))
		}

		return try self.scriptCommandStatus()
	}

	func uninstallScriptCommands() throws -> RaycastScriptCommandStatus {
		for workspace in try self.workspaces.list() {
			guard workspace.raycastScriptCommandConfiguration != nil
			else { continue }
			try self.removeScriptCommand(for: workspace)

			var updatedWorkspace: Workspace = workspace
			updatedWorkspace.raycastScriptCommandConfiguration = nil
			_ = try self.workspaces.save(updatedWorkspace)
		}

		try self.setAutomaticManagement(nil)
		return .init(
			directoryURL: nil,
			managedCommandCount: 0
		)
	}

	func scriptCommandStatus() throws -> RaycastScriptCommandStatus {
		let configurations: [RaycastScriptCommandConfiguration] = try self.workspaces.list()
		.compactMap(\.raycastScriptCommandConfiguration)
		let directoryURLs: Set<URL> = .init(configurations.map(\.directoryURL))
		let managedCommandCount: Int = try self.workspaces.list().reduce(into: 0) { count, workspace in
			guard
				let configuration = workspace.raycastScriptCommandConfiguration,
				try self.isManagedScriptCommand(
					at: self.scriptCommandURL(
						for: workspace,
						in: configuration.directoryURL
					)
				)
			else { return }
			count += 1
		}

		return .init(
			directoryURL: directoryURLs.count == 1 ? directoryURLs.first : nil,
			managedCommandCount: managedCommandCount
		)
	}

	func workspaceCreated(_ workspace: Workspace) throws -> Workspace {
		let primaryWorkspace: Workspace = try self.workspaces.findWorkspace(named: Workspace.primaryName)
		guard let automaticManagement = primaryWorkspace.raycastAutomaticManagement
		else { return workspace }

		return try self.installScriptCommand(
			for: workspace,
			at: automaticManagement.directoryURL,
			fxcodexExecutableURL: automaticManagement.fxcodexExecutableURL
		)
	}

	func workspaceDeleted(_ workspace: Workspace) throws {
		try self.removeScriptCommand(for: workspace)
	}

	func workspaceErased(_ workspace: Workspace) throws {
		try self.removeScriptCommand(for: workspace)
	}

	func workspaceRenamed(
		from oldWorkspace: Workspace,
		to newWorkspace: Workspace
	) throws -> Workspace {
		guard let configuration = oldWorkspace.raycastScriptCommandConfiguration
		else { return newWorkspace }

		try self.removeScriptCommand(for: oldWorkspace)
		return try self.installScriptCommand(
			for: newWorkspace,
			at: configuration.directoryURL,
			fxcodexExecutableURL: configuration.fxcodexExecutableURL
		)
	}
}

extension RaycastIntegration {
	private static var scriptCommandMarker: String {
		"# fxcodex-managed-script-command"
	}

	@MainActor
	private static func applicationURL(for edition: RaycastEdition) -> URL? {
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

		let discoveredURLs: [URL] = NSWorkspace.shared.urlsForApplications(
			withBundleIdentifier: bundleIdentifier
		)
		return (discoveredURLs + [knownURL]).first { url in
			FileManager.default.fileExists(atPath: url.path)
			&& Bundle(url: url)?.bundleIdentifier == bundleIdentifier
		}
	}

	private func installScriptCommand(
		for workspace: Workspace,
		at directoryURL: URL,
		fxcodexExecutableURL: URL
	) throws -> Workspace {
		if let previousConfiguration = workspace.raycastScriptCommandConfiguration {
			let previousURL: URL = self.scriptCommandURL(
				for: workspace,
				in: previousConfiguration.directoryURL
			)
			let newURL: URL = self.scriptCommandURL(
				for: workspace,
				in: directoryURL
			)
			if previousURL != newURL {
				try self.removeManagedScriptCommand(at: previousURL)
			}
		}

		try FileManager.default.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true,
			attributes: nil
		)
		try self.writeScriptCommand(
			to: self.scriptCommandURL(
				for: workspace,
				in: directoryURL
			),
			workspace: workspace,
			fxcodexExecutableURL: fxcodexExecutableURL
		)

		var updatedWorkspace: Workspace = workspace
		updatedWorkspace.raycastScriptCommandConfiguration = .init(
			directoryURL: directoryURL,
			fxcodexExecutableURL: fxcodexExecutableURL
		)
		return try self.workspaces.save(updatedWorkspace)
	}

	private func removeScriptCommand(for workspace: Workspace) throws {
		guard let configuration = workspace.raycastScriptCommandConfiguration
		else { return }
		try self.removeManagedScriptCommand(
			at: self.scriptCommandURL(
				for: workspace,
				in: configuration.directoryURL
			)
		)
	}

	private func removeManagedScriptCommand(at url: URL) throws {
		guard FileManager.default.fileExists(atPath: url.path)
		else { return }
		guard try self.isManagedScriptCommand(at: url)
		else { return }
		try FileManager.default.removeItem(at: url)
		for iconURL in self.scriptCommandIconURLs(forScriptCommandAt: url) {
			guard FileManager.default.fileExists(atPath: iconURL.path)
			else { continue }
			try FileManager.default.removeItem(at: iconURL)
		}
	}

	private func isManagedScriptCommand(at url: URL) throws -> Bool {
		guard FileManager.default.fileExists(atPath: url.path)
		else { return false }
		let contents: String = try .init(contentsOf: url, encoding: .utf8)
		return contents.contains(Self.scriptCommandMarker)
	}

	private func scriptCommandURL(
		for workspace: Workspace,
		in directoryURL: URL
	) -> URL {
		directoryURL.appending(
			path: "fxcodex-open-\(workspace.name).sh",
			directoryHint: .notDirectory
		)
	}

	private func writeScriptCommand(
		to url: URL,
		workspace: Workspace,
		fxcodexExecutableURL: URL
	) throws {
		let iconURLs: [URL] = self.scriptCommandIconURLs(forScriptCommandAt: url)
		try RaycastScriptCommandIcon.light.write(
			to: iconURLs[0],
			options: .atomic
		)
		try RaycastScriptCommandIcon.dark.write(
			to: iconURLs[1],
			options: .atomic
		)

		let contents: String = """
		#!/bin/bash
		\(Self.scriptCommandMarker)

		# Required parameters:
		# @raycast.schemaVersion 1
		# @raycast.title Codex (\(workspace.name.capitalized))
		# @raycast.mode silent

		# Optional parameters:
		# @raycast.packageName fxcodex
		# @raycast.icon ./\(iconURLs[0].lastPathComponent)
		# @raycast.iconDark ./\(iconURLs[1].lastPathComponent)
		# @raycast.description Open or focus the \(workspace.name) Codex workspace

		exec \(self.shellQuote(fxcodexExecutableURL.path)) open \(self.shellQuote(workspace.name))
		"""

		try contents.write(
			to: url,
			atomically: true,
			encoding: .utf8
		)
		try FileManager.default.setAttributes(
			[.posixPermissions: 0o755],
			ofItemAtPath: url.path
		)
	}

	private func scriptCommandIconURLs(
		forScriptCommandAt url: URL
	) -> [URL] {
		let directoryURL: URL = url.deletingLastPathComponent()
		let name: String = url.deletingPathExtension().lastPathComponent
		return [
			directoryURL.appending(path: "\(name)-light.png"),
			directoryURL.appending(path: "\(name)-dark.png"),
		]
	}

	private func setAutomaticManagement(
		_ configuration: RaycastScriptCommandConfiguration?
	) throws {
		var primaryWorkspace: Workspace = try self.workspaces.findWorkspace(
			named: Workspace.primaryName
		)
		primaryWorkspace.raycastAutomaticManagement = configuration
		_ = try self.workspaces.save(primaryWorkspace)
	}

	private func shellQuote(_ value: String) -> String {
		"'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
	}
}

private struct RaycastScriptCommandConfiguration: Equatable, Sendable {
	let directoryURL: URL
	let fxcodexExecutableURL: URL

	init(
		directoryURL: URL,
		fxcodexExecutableURL: URL
	) {
		self.directoryURL = directoryURL.standardizedFileURL
		self.fxcodexExecutableURL = fxcodexExecutableURL.standardizedFileURL
	}
}

extension Workspace {
	fileprivate var raycastIntegration: [String: CodableValue] {
		get { self.integrations["raycast"]?[case: \.dictionary] ?? [:] }
		set {
			if newValue.isEmpty {
				self.integrations.removeValue(forKey: "raycast")
			} else {
				self.integrations["raycast"] = .dictionary(newValue)
			}
		}
	}

	fileprivate var raycastScriptCommandConfiguration: RaycastScriptCommandConfiguration? {
		get {
			guard
				let value = self.raycastIntegration["script_command"]?[case: \.dictionary],
				let directoryPath = value["directory_path"]?[case: \.string],
				let executablePath = value["fxcodex_executable_path"]?[case: \.string]
			else { return nil }
			return .init(
				directoryURL: URL(filePath: directoryPath),
				fxcodexExecutableURL: URL(filePath: executablePath)
			)
		}
		set {
			var integration: [String: CodableValue] = self.raycastIntegration
			if let newValue {
				integration["script_command"] = .dictionary([
					"directory_path": .string(newValue.directoryURL.path),
					"fxcodex_executable_path": .string(newValue.fxcodexExecutableURL.path),
				])
			} else {
				integration.removeValue(forKey: "script_command")
			}
			self.raycastIntegration = integration
		}
	}

	fileprivate var raycastAutomaticManagement: RaycastScriptCommandConfiguration? {
		get {
			guard
				let value = self.raycastIntegration["automatic_script_commands"]?[case: \.dictionary],
				value["enabled"]?[case: \.bool] == true,
				let directoryPath = value["directory_path"]?[case: \.string],
				let executablePath = value["fxcodex_executable_path"]?[case: \.string]
			else { return nil }
			return .init(
				directoryURL: URL(filePath: directoryPath),
				fxcodexExecutableURL: URL(filePath: executablePath)
			)
		}
		set {
			var integration: [String: CodableValue] = self.raycastIntegration
			if let newValue {
				integration["automatic_script_commands"] = .dictionary([
					"enabled": .bool(true),
					"directory_path": .string(newValue.directoryURL.path),
					"fxcodex_executable_path": .string(newValue.fxcodexExecutableURL.path),
				])
			} else {
				integration.removeValue(forKey: "automatic_script_commands")
			}
			self.raycastIntegration = integration
		}
	}
}
