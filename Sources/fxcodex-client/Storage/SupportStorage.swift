import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct SupportStorageClient: Sendable {
	var removeAll: @Sendable () throws -> Void
}

extension DependencyValues {
	private enum SupportStorageClientKey: DependencyKey {
		static var liveValue: SupportStorageClient {
			let storage: SupportStorage = .init(fileManager: .default)
			return .init(removeAll: storage.removeAll)
		}
	}

	var _fxcodexSupport: SupportStorageClient {
		get { self[SupportStorageClientKey.self] }
		set { self[SupportStorageClientKey.self] = newValue }
	}
}

final class SupportStorage: @unchecked Sendable {
	private let fileManager: FileManager

	@Dependency(\._fxcodexPaths)
	private var paths: FXCodexPaths

	init(fileManager: FileManager) {
		self.fileManager = fileManager
	}

	func removeAll() throws {
		let rootURL: URL = self.paths.rootURL.standardizedFileURL

		guard rootURL.pathComponents.count > 2
		else { throw FXCodexError.supportDirectoryInvalid(rootURL) }

		guard self.fileManager.fileExists(atPath: rootURL.path) else { return }
		try self.fileManager.removeItem(at: rootURL)
	}
}
