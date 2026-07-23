import Foundation
import Dependencies

public struct Integrations: Sendable {
	public var raycast: Raycast
	public var attributes: IntegrationAttributes

	public init(
		raycast: Raycast,
		attributes: IntegrationAttributes
	) {
		self.raycast = raycast
		self.attributes = attributes
	}
}

extension DependencyValues {
	public var _fxcodexIntegrations: Integrations {
		get {
			.init(
				raycast: _fxcodexRaycast,
				attributes: _fxcodexIntegrationAttributes
			)
		}
		set {
			self._fxcodexRaycast = newValue.raycast
			self._fxcodexIntegrationAttributes = newValue.attributes
		}
	}
}
