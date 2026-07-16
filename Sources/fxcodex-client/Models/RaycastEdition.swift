public enum RaycastEdition: String, CaseIterable, Codable, Sendable {
	case stable
	case beta

	public var displayName: String {
		switch self {
		case .stable: "Raycast"
		case .beta: "Raycast Beta"
		}
	}
}
