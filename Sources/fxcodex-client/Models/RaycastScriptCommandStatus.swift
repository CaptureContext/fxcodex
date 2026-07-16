import Foundation

public struct RaycastScriptCommandStatus: Codable, Equatable, Sendable {
	public let directoryURL: URL?
	public let managedCommandCount: Int

	public init(
		directoryURL: URL?,
		managedCommandCount: Int
	) {
		self.directoryURL = directoryURL
		self.managedCommandCount = managedCommandCount
	}
}
