internal struct VersionOutput: Encodable {
	internal let version: String

	internal init(
		version: String
	) {
		self.version = version
	}
}
