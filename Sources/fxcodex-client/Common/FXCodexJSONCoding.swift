import Foundation

public enum FXCodexJSONCoding {
	public static func encoder() -> JSONEncoder {
		let encoder: JSONEncoder = .init()
		encoder.keyEncodingStrategy = .convertToSnakeCase
		return encoder
	}
}
