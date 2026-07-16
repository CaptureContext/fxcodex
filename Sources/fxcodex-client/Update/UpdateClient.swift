import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct UpdateClient: Sendable {
	var update: @Sendable (
		_ currentVersion: SemanticVersion,
		_ channel: UpdateChannel,
		_ minimumVersion: SemanticVersion?,
		_ executableURL: URL
	) async throws -> UpdateResult
}

extension DependencyValues {
	private enum UpdateClientKey: DependencyKey {
		static var liveValue: UpdateClient {
			let updater: GitHubReleaseUpdater = .init(
				repository: "CaptureContext/fxcodex",
				fileManager: .default,
				session: .shared
			)
			return .init(update: updater.update)
		}
	}

	var _fxcodexUpdater: UpdateClient {
		get { self[UpdateClientKey.self] }
		set { self[UpdateClientKey.self] = newValue }
	}
}
