import Foundation
import Dependencies

public struct Integrations: Sendable {
	public var raycast: Raycast

	public init(
		raycast: Raycast
	) {
		self.raycast = raycast
	}
}

extension DependencyValues {
	public var _fxcodexIntegrations: Integrations {
		get {
			.init(
				raycast: _fxcodexRaycast
			)
		}
		set {
			self._fxcodexRaycast = newValue.raycast
		}
	}
}
