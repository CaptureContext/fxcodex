import CasePaths

@CasePathable
public enum CodableValue: Codable, Sendable, Equatable {
	case int(Int)
	case float(Float)
	case string(String)
	case bool(Bool)
	case array([CodableValue])
	case dictionary([String: CodableValue])
}

extension CodableValue {
	public func encode(to encoder: any Encoder) throws {
		var container: any SingleValueEncodingContainer = encoder.singleValueContainer()

		switch self {
		case let .int(value):
			try container.encode(value)

		case let .float(value):
			try container.encode(value)

		case let .string(value):
			try container.encode(value)

		case let .bool(value):
			try container.encode(value)

		case let .array(value):
			try container.encode(value)

		case let .dictionary(value):
			try container.encode(value)
		}
	}

	public init(from decoder: any Decoder) throws {
		let container: any SingleValueDecodingContainer = try decoder.singleValueContainer()

		guard !container.decodeNil() else {
			throw DecodingError.valueNotFound(
				Self.self,
				.init(
					codingPath: decoder.codingPath,
					debugDescription: "CodableValue does not support null values."
				)
			)
		}

		if let value = try? container.decode(Bool.self) {
			self = .bool(value)
			return
		}

		if let value = try? container.decode(Int.self) {
			self = .int(value)
			return
		}

		if let value = try? container.decode(Float.self) {
			self = .float(value)
			return
		}

		if let value = try? container.decode(String.self) {
			self = .string(value)
			return
		}

		if var container = try? decoder.unkeyedContainer() {
			var values: [CodableValue] = []
			if let count = container.count {
				values.reserveCapacity(count)
			}

			while !container.isAtEnd {
				values.append(try container.decode(Self.self))
			}

			self = .array(values)
			return
		}

		if let container = try? decoder.container(keyedBy: Key.self) {
			var values: [String: CodableValue] = [:]
			values.reserveCapacity(container.allKeys.count)

			for key in container.allKeys {
				values[key.stringValue] = try container.decode(
					Self.self,
					forKey: key
				)
			}

			self = .dictionary(values)
			return
		}

		throw DecodingError.typeMismatch(
			Self.self,
			.init(
				codingPath: decoder.codingPath,
				debugDescription: "Expected an integer, float, string, boolean, array, or dictionary."
			)
		)
	}
}

extension CodableValue {
	private struct Key: CodingKey {
		let stringValue: String
		let intValue: Int?

		init?(stringValue: String) {
			self.stringValue = stringValue
			self.intValue = nil
		}

		init?(intValue: Int) {
			self.stringValue = String(intValue)
			self.intValue = intValue
		}
	}
}
