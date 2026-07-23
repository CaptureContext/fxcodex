import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct IntegrationAttributes: Sendable {
	public var list: @Sendable () throws -> [String]
	public var get: @Sendable (_ integration: String, _ path: IntegrationAttributePath) throws -> CodableValue
	public var set: @Sendable (_ integration: String, _ path: IntegrationAttributePath, _ value: CodableValue) throws -> Void
	public var remove: @Sendable (_ integration: String, _ path: IntegrationAttributePath) throws -> Void
}

extension DependencyValues {
	private enum IntegrationAttributesKey: DependencyKey {
		static var liveValue: IntegrationAttributes {
			let storage = IntegrationAttributesStorage(fileManager: .default)
			return .init(
				list: storage.integrationIDs,
				get: storage.value,
				set: storage.setValue,
				remove: storage.removeValue
			)
		}
	}

	var _fxcodexIntegrationAttributes: IntegrationAttributes {
		get { self[IntegrationAttributesKey.self] }
		set { self[IntegrationAttributesKey.self] = newValue }
	}
}

final class IntegrationAttributesStorage: @unchecked Sendable {
	private let decoder = JSONDecoder()
	private let encoder: JSONEncoder
	private let fileManager: FileManager
	private let paths: FXCodexPaths
	private let lock: StorageLock

	init(fileManager: FileManager) {
		@Dependency(\._fxcodexPaths)
		var paths

		let encoder = FXCodexJSONCoding.encoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		self.encoder = encoder
		self.fileManager = fileManager
		self.paths = paths
		self.lock = StorageLock(fileManager: fileManager, paths: paths)
	}

	func integrationIDs() throws -> [String] {
		try self.prepare()
		return try self.loadConfiguration().integrations.keys.sorted()
	}

	func value(integration: String, path: IntegrationAttributePath) throws -> CodableValue {
		try self.prepare()

		guard var value = try self.loadConfiguration().integrations[integration] else {
			throw FXCodexError.integrationAttributeNotFound(Self.displayPath(integration, path))
		}

		for component in path.components {
			value = try Self.apply(component, to: value, displayPath: Self.displayPath(integration, path))
		}

		return value
	}

	func setValue(integration: String, path: IntegrationAttributePath, value: CodableValue) throws {
		try Self.requireMutable(path)
		try self.prepare()
		try self.lock.withLock {
			var configuration = try self.loadConfiguration()

			if path.components.isEmpty {
				configuration.integrations[integration] = value

			} else {
				let root = configuration.integrations[integration] ?? .dictionary([:])
				configuration.integrations[integration] = try Self.setting(
					value,
					in: root,
					components: path.components[...],
					displayPath: Self.displayPath(integration, path)
				)
			}

			try self.save(configuration)
		}
	}

	func removeValue(integration: String, path: IntegrationAttributePath) throws {
		try Self.requireMutable(path)
		try self.prepare()
		try self.lock.withLock {
			var configuration = try self.loadConfiguration()

			guard let root = configuration.integrations[integration] else {
				throw FXCodexError.integrationAttributeNotFound(Self.displayPath(integration, path))
			}

			if path.components.isEmpty {
				configuration.integrations.removeValue(forKey: integration)

			} else {
				configuration.integrations[integration] = try Self.removing(
					from: root,
					components: path.components[...],
					displayPath: Self.displayPath(integration, path)
				)
			}

			try self.save(configuration)
		}
	}
}

private extension IntegrationAttributesStorage {
	func prepare() throws {
		try Migrator(fileManager: self.fileManager, paths: self.paths).migrateIfNeeded()
	}

	func loadConfiguration() throws -> StorageConfiguration {
		try self.decoder.decode(StorageConfiguration.self, from: Data(contentsOf: self.paths.configurationURL))
	}

	func save(_ configuration: StorageConfiguration) throws {
		try self.encoder.encode(configuration).write(to: self.paths.configurationURL, options: [.atomic])
	}

	static func apply(
		_ component: IntegrationAttributePath.Component,
		to value: CodableValue,
		displayPath: String
	) throws -> CodableValue {
		switch component {
		case let .member(key), let .key(key):
			guard case let .dictionary(dictionary) = value, let result = dictionary[key] else {
				throw FXCodexError.integrationAttributeNotFound(displayPath)
			}
			return result

		case let .index(index):
			guard case let .array(array) = value, array.indices.contains(index) else {
				throw FXCodexError.integrationAttributeNotFound(displayPath)
			}
			return array[index]

		case let .function(function):
			return try Self.apply(function, to: value, displayPath: displayPath)
		}
	}

	static func apply(
		_ function: IntegrationAttributePath.Function,
		to value: CodableValue,
		displayPath: String
	) throws -> CodableValue {
		switch (function, value) {
		case let (.count, .array(array)):
			.int(array.count)
		case let (.count, .dictionary(dictionary)):
			.int(dictionary.count)
		case let (.count, .string(string)):
			.int(string.count)
		case let (.first, .array(array)):
			try array.first ?? Self.notFound(displayPath)
		case let (.last, .array(array)):
			try array.last ?? Self.notFound(displayPath)
		case let (.first, .string(string)):
			try string.first.map { .string(String($0)) } ?? Self.notFound(displayPath)
		case let (.last, .string(string)):
			try string.last.map { .string(String($0)) } ?? Self.notFound(displayPath)
		case let (.keys, .dictionary(dictionary)):
			.array(dictionary.keys.sorted().map(CodableValue.string))
		case let (.values, .dictionary(dictionary)):
			.array(dictionary.keys.sorted().compactMap { dictionary[$0] })
		default:
			throw FXCodexError.invalidAttributePath(displayPath)
		}
	}

	static func setting(
		_ newValue: CodableValue,
		in current: CodableValue,
		components: ArraySlice<IntegrationAttributePath.Component>,
		displayPath: String
	) throws -> CodableValue {
		guard let component = components.first else { return newValue }
		let remaining = components.dropFirst()

		switch component {
		case let .member(key), let .key(key):
			var dictionary: [String: CodableValue]

			if case let .dictionary(existing) = current {
				dictionary = existing
			} else {
				throw FXCodexError.invalidAttributePath(displayPath)
			}

			let child = dictionary[key] ?? .dictionary([:])
			dictionary[key] = try Self.setting(
				newValue,
				in: child,
				components: remaining,
				displayPath: displayPath
			)

			return .dictionary(dictionary)

		case let .index(index):
			guard case var .array(array) = current, index <= array.count else {
				throw FXCodexError.invalidAttributePath(displayPath)
			}
			if index == array.count {
				guard remaining.isEmpty else { throw FXCodexError.invalidAttributePath(displayPath) }
				array.append(newValue)

			} else {
				array[index] = try Self.setting(
					newValue,
					in: array[index],
					components: remaining,
					displayPath: displayPath
				)
			}

			return .array(array)

		case .function:
			throw FXCodexError.invalidAttributePath(displayPath)
		}
	}

	static func removing(
		from current: CodableValue,
		components: ArraySlice<IntegrationAttributePath.Component>,
		displayPath: String
	) throws -> CodableValue {
		guard let component = components.first else { return current }
		let remaining = components.dropFirst()

		switch component {
		case let .member(key), let .key(key):
			guard case var .dictionary(dictionary) = current, let child = dictionary[key] else {
				throw FXCodexError.integrationAttributeNotFound(displayPath)
			}
			if remaining.isEmpty {
				dictionary.removeValue(forKey: key)

			} else {
				dictionary[key] = try Self.removing(
					from: child,
					components: remaining,
					displayPath: displayPath
				)
			}

			return .dictionary(dictionary)

		case let .index(index):
			guard case var .array(array) = current, array.indices.contains(index) else {
				throw FXCodexError.integrationAttributeNotFound(displayPath)
			}
			if remaining.isEmpty {
				array.remove(at: index)

			} else {
				array[index] = try Self.removing(
					from: array[index],
					components: remaining,
					displayPath: displayPath
				)
			}

			return .array(array)

		case .function:
			throw FXCodexError.invalidAttributePath(displayPath)
		}
	}

	static func requireMutable(_ path: IntegrationAttributePath) throws {
		guard
			!path.components.contains(where: {
				if case .function = $0 { return true }
				return false
			})
		else { throw FXCodexError.invalidAttributePath(path.rawValue) }
	}

	static func displayPath(_ integration: String, _ path: IntegrationAttributePath) -> String {
		path.rawValue.isEmpty ? integration : "\(integration).\(path.rawValue)"
	}

	static func notFound(_ path: String) throws -> CodableValue {
		throw FXCodexError.integrationAttributeNotFound(path)
	}
}
