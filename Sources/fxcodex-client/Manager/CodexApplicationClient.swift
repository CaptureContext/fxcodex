import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct CodexApplicationClient: Sendable {
	var applicationURL: @Sendable () async -> URL?
	var rename: @Sendable (CodexApplicationName) async throws -> CodexApplicationRenameResult
	var open: @Sendable (Workspace) async throws -> Int32
	var runningProcessID: @Sendable (Workspace) async throws -> Int32?
	var removeRecord: @Sendable (_ forWorkspaceNamed: String) async throws -> Void
	var renameRecord: @Sendable (_ from: String, _ to: String) async throws -> Void
}

extension DependencyValues {
	private enum CodexApplicationClientKey: DependencyKey {
		static var liveValue: CodexApplicationClient {
			.init(
				applicationURL: {
					let controller: CodexApplicationController = await .init()
					return await controller.applicationURL()
				},
				rename: {
					let controller: CodexApplicationController = await .init()
					return try await controller.rename(to: $0)
				},
				open: {
					let controller: CodexApplicationController = await .init()
					return try await controller.open(workspace: $0)
				},
				runningProcessID: {
					let controller: CodexApplicationController = await .init()
					return try await controller.runningProcessID(for: $0)
				},
				removeRecord: {
					let controller: CodexApplicationController = await .init()
					try await controller.removeRecord(forWorkspaceNamed: $0)
				},
				renameRecord: {
					let controller: CodexApplicationController = await .init()
					try await controller.renameRecord(from: $0, to: $1)
				}
			)
		}
	}

	var _fxcodexApplication: CodexApplicationClient {
		get { self[CodexApplicationClientKey.self] }
		set { self[CodexApplicationClientKey.self] = newValue }
	}
}
