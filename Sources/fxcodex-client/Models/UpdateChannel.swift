public enum UpdateChannel: String, Codable, Sendable {
	case patch
	case minor
	case major
	case latest
}
