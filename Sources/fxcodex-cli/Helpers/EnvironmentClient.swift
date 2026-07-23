import Dependencies
import Foundation

internal struct EnvironmentClient: Sendable {
	internal var values: @Sendable () -> [String: String]

	internal init(
		values: @escaping @Sendable () -> [String: String]
	) {
		self.values = values
	}
}

extension DependencyValues {
	private enum EnvironmentClientKey: DependencyKey {
		static var liveValue: EnvironmentClient {
			.init(values: { ProcessInfo.processInfo.environment })
		}

		static var testValue: EnvironmentClient {
			.init(values: { [:] })
		}
	}

	internal var _fxcodexEnvironment: EnvironmentClient {
		get { self[EnvironmentClientKey.self] }
		set { self[EnvironmentClientKey.self] = newValue }
	}
}

internal func currentEnvironment() -> [String: String] {
	@Dependency(\._fxcodexEnvironment)
	var environment: EnvironmentClient

	return environment.values()
}
