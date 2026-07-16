import Foundation

public struct RaycastApplicationStatus: Codable, Equatable, Sendable {
	public let edition: RaycastEdition
	public let applicationURL: URL?
	public let version: String?

	public init(
		edition: RaycastEdition,
		applicationURL: URL?,
		version: String?
	) {
		self.edition = edition
		self.applicationURL = applicationURL
		self.version = version
	}
}
