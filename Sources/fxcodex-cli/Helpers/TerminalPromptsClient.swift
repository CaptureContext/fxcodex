import ArgumentParser
import Darwin
import Dependencies
import Foundation
import Promptberry

internal struct TerminalPromptOption: Equatable, Sendable {
	internal let value: String
	internal let label: String
	internal let hint: String?

	internal init(
		value: String,
		label: String,
		hint: String?
	) {
		self.value = value
		self.label = label
		self.hint = hint
	}
}

internal struct TerminalPromptsClient: Sendable {
	internal var select: @Sendable (String, [TerminalPromptOption]) throws -> String?
	internal var multiselect: @Sendable (String, [TerminalPromptOption]) throws -> [String]?
	internal var confirm: @Sendable (String) throws -> Bool?
	internal var text: @Sendable (String, String) throws -> String?

	internal init(
		select: @escaping @Sendable (String, [TerminalPromptOption]) throws -> String?,
		multiselect: @escaping @Sendable (String, [TerminalPromptOption]) throws -> [String]?,
		confirm: @escaping @Sendable (String) throws -> Bool?,
		text: @escaping @Sendable (String, String) throws -> String? = { _, _ in
			throw ValidationError("Text input is not configured.")
		}
	) {
		self.select = select
		self.multiselect = multiselect
		self.confirm = confirm
		self.text = text
	}
}

extension DependencyValues {
	private enum TerminalPromptsClientKey: DependencyKey {
		static var liveValue: TerminalPromptsClient {
			.init(
				select: { message, options in
					try Self.requireInteractiveTerminal()
					do {
						return try Promptberry.select(
							message,
							options: options.map { option in
								.init(
									value: option.value,
									label: option.label,
									hint: option.hint
								)
							}
						)
					} catch is PromptCancelled {
						return nil
					}
				},
				multiselect: { message, options in
					try Self.requireInteractiveTerminal()
					do {
						return try Promptberry.multiselect(
							message,
							options: options.map { option in
								.init(
									value: option.value,
									label: option.label,
									hint: option.hint
								)
							},
							required: true
						)
					} catch is PromptCancelled {
						return nil
					}
				},
				confirm: { message in
					try Self.requireInteractiveTerminal()
					do {
						return try Promptberry.confirm(
							message,
							initialValue: false
						)
					} catch is PromptCancelled {
						return nil
					}
				},
				text: { message, placeholder in
					try Self.requireInteractiveTerminal()
					do {
						return try Promptberry.text(
							message,
							placeholder: placeholder,
							validate: { value in
								value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
									? "A value is required."
									: nil
							}
						)
					} catch is PromptCancelled {
						return nil
					}
				}
			)
		}

		private static func requireInteractiveTerminal() throws {
			guard interactiveTerminalAvailable() else {
				throw ValidationError(
					"Interactive input requires a terminal. Provide the required values explicitly."
				)
			}
		}
	}

	internal var _fxcodexTerminalPrompts: TerminalPromptsClient {
		get { self[TerminalPromptsClientKey.self] }
		set { self[TerminalPromptsClientKey.self] = newValue }
	}
}

internal func interactiveTerminalAvailable() -> Bool {
	isatty(STDIN_FILENO) != 0 && isatty(STDOUT_FILENO) != 0
}
