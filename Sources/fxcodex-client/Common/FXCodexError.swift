import Foundation

public enum FXCodexError: Error, Equatable, LocalizedError, Sendable {
	case applicationNotFound
	case applicationBundleMismatch(URL)
	case ambiguousApplicationInstances([Int32])
	case codexExecutableNotFound
	case homebrewNotFound
	case invalidWorkspaceName(String)
	case primaryWorkspaceMutation
	case raycastBetaUnsupportedPlatform
	case raycastScriptCommandDirectoryMissing
	case supportDirectoryInvalid(URL)
	case updateArchitectureUnsupported
	case updateAssetMissing(String)
	case updateChecksumInvalid
	case updateChecksumMismatch
	case updateExecutableInvalid(URL)
	case updateRequestFailed(Int)
	case workspaceAlreadyExists(String)
	case workspaceIsRunning(String)
	case workspaceNotFound(String)

	public var code: String {
		switch self {
		case .applicationNotFound:
			"application_not_found"

		case .applicationBundleMismatch:
			"application_bundle_mismatch"

		case .ambiguousApplicationInstances:
			"ambiguous_application_instances"

		case .codexExecutableNotFound:
			"codex_executable_not_found"

		case .homebrewNotFound:
			"homebrew_not_found"

		case .invalidWorkspaceName:
			"invalid_workspace_name"

		case .primaryWorkspaceMutation:
			"primary_workspace_mutation"

		case .raycastBetaUnsupportedPlatform:
			"raycast_beta_unsupported_platform"

		case .raycastScriptCommandDirectoryMissing:
			"raycast_script_command_directory_missing"

		case .supportDirectoryInvalid:
			"support_directory_invalid"

		case .updateArchitectureUnsupported:
			"update_architecture_unsupported"

		case .updateAssetMissing:
			"update_asset_missing"

		case .updateChecksumInvalid:
			"update_checksum_invalid"

		case .updateChecksumMismatch:
			"update_checksum_mismatch"

		case .updateExecutableInvalid:
			"update_executable_invalid"

		case .updateRequestFailed:
			"update_request_failed"

		case .workspaceAlreadyExists:
			"workspace_already_exists"

		case .workspaceIsRunning:
			"workspace_is_running"

		case .workspaceNotFound:
			"workspace_not_found"
		}
	}

	public var errorDescription: String? {
		switch self {
		case .applicationNotFound:
			"No application with bundle identifier com.openai.codex was found."

		case let .applicationBundleMismatch(url):
			"Application at '\(url.path)' is not Codex and was not renamed."

		case let .ambiguousApplicationInstances(processIDs):
			"Multiple unrecognized Codex instances are running: \(processIDs.map(String.init).joined(separator: ", "))."

		case .codexExecutableNotFound:
			"The codex executable could not be found in PATH."

		case .homebrewNotFound:
			"Homebrew could not be found in PATH."

		case let .invalidWorkspaceName(name):
			"Invalid workspace name '\(name)'. Use lowercase letters, numbers, and hyphens."

		case .primaryWorkspaceMutation:
			"The primary workspace cannot be created, deleted, or renamed."

		case .raycastBetaUnsupportedPlatform:
			"Raycast Beta currently requires Apple silicon and macOS Tahoe or later."

		case .raycastScriptCommandDirectoryMissing:
			"No Raycast Script Commands directory is configured."

		case let .supportDirectoryInvalid(url):
			"Refusing to remove unsafe support directory '\(url.path)'."

		case .updateArchitectureUnsupported:
			"No fxcodex release artifact is available for this architecture."

		case let .updateAssetMissing(name):
			"The GitHub Release does not contain required asset '\(name)'."

		case .updateChecksumInvalid:
			"The downloaded fxcodex checksum is invalid."

		case .updateChecksumMismatch:
			"The downloaded fxcodex binary does not match its SHA-256 checksum."

		case let .updateExecutableInvalid(url):
			"The current fxcodex executable at '\(url.path)' is not a regular file."

		case let .updateRequestFailed(statusCode):
			"The GitHub Releases request failed with HTTP status \(statusCode)."

		case let .workspaceAlreadyExists(name):
			"Workspace '\(name)' already exists."

		case let .workspaceIsRunning(name):
			"Workspace '\(name)' is currently open. Close it before continuing."

		case let .workspaceNotFound(name):
			"Workspace '\(name)' does not exist."
		}
	}
}
