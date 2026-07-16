public enum CodexApplicationName: String, Codable, Sendable {
	case chatGPT = "ChatGPT.app"
	case codex = "Codex.app"
}

extension CodexApplicationName {
	public var alternative: Self {
		switch self {
		case .chatGPT:
			.codex

		case .codex:
			.chatGPT
		}
	}
}
