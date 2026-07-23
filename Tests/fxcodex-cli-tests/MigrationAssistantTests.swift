import ArgumentParser
import Dependencies
import FXCodexClient
import Testing
@testable
import FXCodexCLI

@Suite("Migration assistant")
struct MigrationAssistantTests {
	@Test("Interactive migration explains the plan and requires confirmation")
	func interactiveMigration() async throws {
		let prepared = LockIsolated(false)
		let migrated = LockIsolated<[SchemaVersion]>([])
		let confirmation = LockIsolated("")
		var client = FXCodexClient()
		client.storageMigrationPlan = { Self.plan() }
		client.migrateStorage = { migration in
			migrated.withValue { $0.append(migration.destinationVersion) }
		}
		client.prepareStorage = { prepared.setValue(true) }

		try await withDependencies {
			$0.fxCodexClient = client
			$0._fxcodexTerminalPrompts = .init(
				select: { _, _ in nil },
				multiselect: { _, _ in nil },
				confirm: { message in
					confirmation.setValue(message)
					return true
				}
			)
		} operation: {
			try await MigrationAssistant.prepareStorage(client: client, interactive: true)
		}

		#expect(prepared.value)
		#expect(migrated.value == [.v2_0])
		#expect(confirmation.value.contains("1.0"))
		#expect(confirmation.value.contains("2.0"))
	}

	@Test("Declining migration prevents command preparation")
	func declinedMigration() async throws {
		let prepared = LockIsolated(false)
		let migrated = LockIsolated<[SchemaVersion]>([])
		var client = FXCodexClient()
		client.storageMigrationPlan = { Self.plan() }
		client.migrateStorage = { migration in
			migrated.withValue { $0.append(migration.destinationVersion) }
		}
		client.prepareStorage = { prepared.setValue(true) }

		await #expect(throws: CleanExit.self) {
			try await withDependencies {
				$0.fxCodexClient = client
				$0._fxcodexTerminalPrompts = .init(
					select: { _, _ in nil },
					multiselect: { _, _ in nil },
					confirm: { _ in false }
				)
			} operation: {
				try await MigrationAssistant.prepareStorage(client: client, interactive: true)
			}
		}
		#expect(!prepared.value)
		#expect(migrated.value.isEmpty)
	}

	@Test("Non-interactive callers run migrations that need no answers")
	func nonInteractiveMigration() async throws {
		let prepared = LockIsolated(false)
		let migrated = LockIsolated<[SchemaVersion]>([])
		var client = FXCodexClient()
		client.storageMigrationPlan = { Self.plan() }
		client.migrateStorage = { migration in
			migrated.withValue { $0.append(migration.destinationVersion) }
		}
		client.prepareStorage = { prepared.setValue(true) }

		try await MigrationAssistant.prepareStorage(client: client, interactive: false)
		#expect(prepared.value)
		#expect(migrated.value == [.v2_0])
	}

	@Test("Non-interactive callers stop when a migration needs answers")
	func requiredInteraction() async throws {
		let prepared = LockIsolated(false)
		var client = FXCodexClient()
		client.storageMigrationPlan = {
			.init(
				sourceVersion: .v1_0,
				destinationVersion: .v2_0,
				migrations: [
					.init(
						sourceVersion: .v1_0,
						destinationVersion: .v2_0,
						steps: ["Choose a value"],
						requiresUserInput: true
					),
				]
			)
		}
		client.prepareStorage = { prepared.setValue(true) }

		await #expect(throws: ValidationError.self) {
			try await MigrationAssistant.prepareStorage(client: client, interactive: false)
		}
		#expect(!prepared.value)
	}

	private static func plan() -> StorageMigrationPlan {
		.init(
			sourceVersion: .v1_0,
			destinationVersion: .v2_0,
			migrations: [
				.init(
					sourceVersion: .v1_0,
					destinationVersion: .v2_0,
					steps: ["Assign IDs", "Write configuration"],
					requiresUserInput: false
				),
			]
		)
	}
}
