import ArgumentParser
import Dependencies
import FXCodexClient
import Testing
@testable
import FXCodexCLI

@Suite("Integration attributes command")
struct IntegrationAttributesCommandTests {
	@Test("Get offers available integration identifiers and manual entry")
	func getIntegrationSelection() async throws {
		let options = LockIsolated<[TerminalPromptOption]>([])
		let requested = LockIsolated("")
		var attributes = IntegrationAttributes()
		attributes.list = { ["custom", "raycast"] }
		attributes.get = { integration, _ in
			requested.setValue(integration)
			return .dictionary(["enabled": .bool(true)])
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: .init(), attributes: attributes)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in nil },
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, values in
					options.setValue(values)
					return "raycast"
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Attributes.Get = try .parse([])
			try await command.run()
		}

		#expect(options.value.map(\.label) == ["custom", "raycast", "Enter manually…"])
		#expect(requested.value == "raycast")
	}

	@Test("Set prompts for omitted identifier and value")
	func setMissingValues() async throws {
		let storedIntegration = LockIsolated("")
		let storedValue = LockIsolated<CodableValue?>(nil)
		var attributes = IntegrationAttributes()
		attributes.list = { [] }
		attributes.set = { integration, _, value in
			storedIntegration.setValue(integration)
			storedValue.setValue(value)
		}

		let answers = LockIsolated(["custom", "{\"enabled\":true}"])
		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: .init(), attributes: attributes)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in "__fxcodex_manual_integration__" },
				multiselect: { _, _ in nil },
				confirm: { _ in nil },
				text: { _, _ in answers.withValue { $0.removeFirst() } }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Attributes.Set = try .parse([])
			try await command.run()
		}

		#expect(storedIntegration.value == "custom")
		#expect(storedValue.value == .dictionary(["enabled": .bool(true)]))
	}

	@Test("Get offers registered integrations when storage is empty")
	func registeredIntegrationSelection() async throws {
		let options = LockIsolated<[TerminalPromptOption]>([])
		var attributes = IntegrationAttributes()
		attributes.list = { [] }
		attributes.get = { _, _ in .dictionary([:]) }

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: .init(), attributes: attributes)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, values in
					options.setValue(values)
					return "raycast"
				},
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Attributes.Get = try .parse([])
			try await command.run()
		}

		#expect(options.value.map(\.label) == ["raycast", "Enter manually…"])
	}

	@Test("JSON get rejects a missing identifier without prompting")
	func jsonRequiresIdentifier() async throws {
		let command: AppCommand.IntegrationsCommand.Attributes.Get = try .parse(["--json"])
		await #expect(throws: ValidationError.self) {
			try await withDependencies {
				$0.fxCodexClient = .init()
				$0._fxcodexTerminalPrompts = .init(
					select: { _, _ in nil },
					multiselect: { _, _ in nil },
					confirm: { _ in nil }
				)
			} operation: {
				try await command.run()
			}
		}
	}

	@Test("JSON get, set, and remove execute with explicit values")
	func jsonLifecycle() async throws {
		let requestedPaths = LockIsolated<[String]>([])
		let storedValue = LockIsolated<CodableValue?>(nil)
		let removed = LockIsolated(false)
		var attributes = IntegrationAttributes()
		attributes.get = { integration, path in
			#expect(integration == "raycast")
			requestedPaths.withValue { $0.append(path.rawValue) }
			return storedValue.value ?? .dictionary([:])
		}
		attributes.set = { integration, path, value in
			#expect(integration == "raycast")
			requestedPaths.withValue { $0.append(path.rawValue) }
			storedValue.setValue(value)
		}
		attributes.remove = { integration, path in
			#expect(integration == "raycast")
			requestedPaths.withValue { $0.append(path.rawValue) }
			removed.setValue(true)
		}

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: .init(), attributes: attributes)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in nil },
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let set: AppCommand.IntegrationsCommand.Attributes.Set = try .parse([
				"raycast",
				"{\"enabled\":true}",
				"--path",
				"settings",
				"--json",
			])
			try await set.run()

			let get: AppCommand.IntegrationsCommand.Attributes.Get = try .parse([
				"raycast",
				"--path",
				"settings",
				"--json",
			])
			try await get.run()

			let remove: AppCommand.IntegrationsCommand.Attributes.Remove = try .parse([
				"raycast",
				"--path",
				"settings",
				"--json",
			])
			try await remove.run()
		}

		#expect(storedValue.value == .dictionary(["enabled": .bool(true)]))
		#expect(requestedPaths.value == ["settings", "settings", "settings"])
		#expect(removed.value)
	}

	@Test("Interactive remove executes an explicit request")
	func explicitRemove() async throws {
		let removed = LockIsolated(false)
		var attributes = IntegrationAttributes()
		attributes.remove = { _, _ in removed.setValue(true) }

		try await withDependencies {
			$0.fxCodexClient = .init()
			$0._fxcodexIntegrations = .init(raycast: .init(), attributes: attributes)
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in nil },
				multiselect: { _, _ in nil },
				confirm: { _ in nil }
			)
		} operation: {
			let command: AppCommand.IntegrationsCommand.Attributes.Remove = try .parse([
				"raycast",
				"--path",
				"settings",
			])
			try await command.run()
		}

		#expect(removed.value)
	}
}
