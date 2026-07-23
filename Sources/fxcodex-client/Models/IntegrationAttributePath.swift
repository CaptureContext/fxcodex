import Foundation
import Parsing

public struct IntegrationAttributePath: Equatable, Sendable {
	public enum Component: Equatable, Sendable {
		case member(String)
		case key(String)
		case index(Int)
		case function(Function)
	}

	public enum Function: String, CaseIterable, Sendable {
		case count
		case first
		case last
		case keys
		case values
	}

	public let components: [Component]
	public let rawValue: String

	public init(_ rawValue: String) throws {
		self.rawValue = rawValue
		var input = rawValue[...]
		self.components = try AttributePathParser().parse(&input)
	}
}

private struct AttributePathParser: Parser {
	func parse(_ input: inout Substring) throws -> [IntegrationAttributePath.Component] {
		let original = String(input)
		var components: [IntegrationAttributePath.Component] = []
		var expectsComponent = true

		while !input.isEmpty {
			if input.first == "." {
				guard !expectsComponent else { throw FXCodexError.invalidAttributePath(original) }
				input.removeFirst()
				expectsComponent = true
				continue
			}

			let component: IntegrationAttributePath.Component
			switch input.first {
			case "[":
				component = try self.parseBracket(&input, original: original)

			case "(":
				component = try self.parseFunction(&input, original: original)

			default:
				let end = input.firstIndex(where: { $0 == "." || $0 == "[" || $0 == "(" }) ?? input.endIndex
				let member = String(input[..<end])
				guard Self.isMember(member) else { throw FXCodexError.invalidAttributePath(original) }
				input.removeSubrange(..<end)
				component = .member(member)
			}

			components.append(component)
			expectsComponent = false
		}

		guard !expectsComponent || components.isEmpty
		else { throw FXCodexError.invalidAttributePath(original) }

		return components
	}

	private func parseBracket(
		_ input: inout Substring,
		original: String
	) throws -> IntegrationAttributePath.Component {
		guard let close = input.firstIndex(of: "]")
		else { throw FXCodexError.invalidAttributePath(original) }

		let content = input[input.index(after: input.startIndex)..<close]
		input.removeSubrange(...close)
		let parts = content.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
		guard parts.count == 2 else { throw FXCodexError.invalidAttributePath(original) }
		let kind = parts[0].trimmingCharacters(in: .whitespaces)
		let value = parts[1].trimmingCharacters(in: .whitespaces)

		switch kind {
		case "key":
			guard let key = Self.parseKey(value), !key.isEmpty else {
				throw FXCodexError.invalidAttributePath(original)
			}
			return .key(key)

		case "idx":
			guard let index = Int(value), index >= 0, String(index) == value else {
				throw FXCodexError.invalidAttributePath(original)
			}
			return .index(index)

		default:
			throw FXCodexError.invalidAttributePath(original)
		}
	}

	private func parseFunction(
		_ input: inout Substring,
		original: String
	) throws -> IntegrationAttributePath.Component {
		guard let close = input.firstIndex(of: ")")
		else { throw FXCodexError.invalidAttributePath(original) }

		let name = String(input[input.index(after: input.startIndex)..<close])
		input.removeSubrange(...close)
		guard let function = IntegrationAttributePath.Function(rawValue: name) else {
			throw FXCodexError.invalidAttributePath(original)
		}
		return .function(function)
	}

	private static func isMember(_ value: String) -> Bool {
		guard let first = value.first, first.isLetter || first == "_" else { return false }
		return value.dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
	}

	private static func parseKey(_ value: String) -> String? {
		guard value.first == "\"" else { return value }
		guard let data = value.data(using: .utf8) else { return nil }
		return try? JSONDecoder().decode(String.self, from: data)
	}
}
