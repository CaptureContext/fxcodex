import Foundation

/// How `openURL` handed a link to a workspace's Codex instance.
public struct URLDelivery: Codable, Equatable, Sendable {
	public enum Method: String, Codable, Equatable, Sendable {
		/// The instance was running and received a `kAEGetURL` Apple Event addressed by process ID.
		case appleEvent = "apple-event"

		/// The instance was not running and launched with the link.
		case launch
	}

	public let workspace: Workspace
	public let url: URL
	public let processID: Int32
	public let method: Method

	public init(
		workspace: Workspace,
		url: URL,
		processID: Int32,
		method: Method
	) {
		self.workspace = workspace
		self.url = url
		self.processID = processID
		self.method = method
	}
}
