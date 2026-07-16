public struct FXCodexPreferences: Codable, Equatable, Sendable {
	public var autoRename: Bool
	public var autoUpdate: AutoUpdatePolicy

	public init(
		autoRename: Bool = false,
		autoUpdate: AutoUpdatePolicy = .disabled
	) {
		self.autoRename = autoRename
		self.autoUpdate = autoUpdate
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		self.autoRename = try container.decodeIfPresent(
			Bool.self,
			forKey: .autoRename
		)
		?? false
		self.autoUpdate = try container.decodeIfPresent(
			AutoUpdatePolicy.self,
			forKey: .autoUpdate
		)
		?? .disabled
	}
}

extension FXCodexPreferences {
	private enum CodingKeys: String, CodingKey {
		case autoRename = "auto_rename"
		case autoUpdate = "auto_update"
	}
}
