import ArgumentParser
import Dependencies
import Foundation

internal enum SelfUninstallMethod: String, Encodable, Sendable {
	case direct
	case homebrew
}

internal struct SelfInstallationClient: Sendable {
	internal var uninstall: @Sendable (URL) throws -> SelfUninstallMethod
}

extension DependencyValues {
	private enum SelfInstallationClientKey: DependencyKey {
		static var liveValue: SelfInstallationClient {
			.init(uninstall: { executableURL in
				let executableURL: URL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
				if Self.isHomebrewManaged(executableURL) {
					let exitCode: Int32 = try runProcess(.init(
						executable: "brew",
						arguments: ["uninstall", "fxcodex"],
						environment: [:]
					))
					guard exitCode == 0 else { throw ExitCode(exitCode) }
					return .homebrew
				}

				try FileManager.default.removeItem(at: executableURL)
				return .direct
			})
		}

		private static func isHomebrewManaged(_ executableURL: URL) -> Bool {
			let components: [String] = executableURL.pathComponents
			guard let cellarIndex = components.firstIndex(of: "Cellar")
			else { return false }
			return components.indices.contains(cellarIndex + 1)
			&& components[cellarIndex + 1] == "fxcodex"
		}
	}

	internal var _fxcodexSelfInstallation: SelfInstallationClient {
		get { self[SelfInstallationClientKey.self] }
		set { self[SelfInstallationClientKey.self] = newValue }
	}
}
