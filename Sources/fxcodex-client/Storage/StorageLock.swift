import Darwin
import Foundation

final class StorageLock: @unchecked Sendable {
	private let fileManager: FileManager
	private let paths: FXCodexPaths

	init(fileManager: FileManager, paths: FXCodexPaths) {
		self.fileManager = fileManager
		self.paths = paths
	}

	func withLock<Value>(_ operation: () throws -> Value) throws -> Value {
		try self.fileManager.createDirectory(
			at: self.paths.rootURL,
			withIntermediateDirectories: true,
			attributes: [.posixPermissions: 0o700]
		)
		let descriptor = Darwin.open(
			self.paths.storageLockURL.path,
			O_CREAT | O_RDWR,
			S_IRUSR | S_IWUSR
		)
		guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
		defer { Darwin.close(descriptor) }
		guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
			throw CocoaError(.fileLocking)
		}
		defer { Darwin.lockf(descriptor, F_ULOCK, 0) }
		return try operation()
	}
}
