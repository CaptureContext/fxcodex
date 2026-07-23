import ArgumentParser
import Dependencies
import FXCodexClient

internal enum MigrationAssistant {
	private enum MigrationV1 {
		static let title = "Stable workspace identities"
	}

	internal static func prepareStorage(
		client: FXCodexClient,
		interactive: Bool = interactiveTerminalAvailable() && !globalMachineOutputRequested()
	) async throws {
		guard let plan = try await client.storageMigrationPlan() else {
			try await client.prepareStorage()
			return
		}

		guard interactive else {
			guard !plan.requiresUserInput else {
				throw ValidationError(
					"Storage schema \(plan.sourceVersion) requires an interactive migration to \(plan.destinationVersion). Run fxcodex in a terminal first."
				)
			}

			for migration in plan.migrations {
				try await client.migrateStorage(migration)
			}

			try await client.prepareStorage()
			return
		}

		@Dependency(\._fxcodexTerminalPrompts)
		var prompts: TerminalPromptsClient

		let reporter = await TerminalReporter()
		await reporter.warning(
			"Storage schema \(plan.sourceVersion) must be migrated to \(plan.destinationVersion) before this command can run."
		)

		var stepNumber = 0
		let stepCount = plan.migrations.reduce(0) { $0 + $1.steps.count }

		for migration in plan.migrations {
			await reporter.info(
				"\(migration.sourceVersion) → \(migration.destinationVersion): \(Self.title(for: migration))"
			)
			for step in migration.steps {
				stepNumber += 1
				await reporter.info("  [\(stepNumber)/\(stepCount)] \(step)")
			}
		}

		guard
			try prompts.confirm(
				"Proceed with migration from schema \(plan.sourceVersion) to \(plan.destinationVersion)?"
			) == true
		else {
			throw CleanExit.message("Migration cancelled. No command was run.")
		}

		for (index, migration) in plan.migrations.enumerated() {
			await reporter.info(
				"Migrating \(migration.sourceVersion) → \(migration.destinationVersion)…"
			)
			try await client.migrateStorage(migration)
			await reporter.success(
				"[\(index + 1)/\(plan.migrations.count)] Migrated to schema \(migration.destinationVersion)."
			)
		}

		try await client.prepareStorage()
		await reporter.success("Storage migrated to schema \(plan.destinationVersion).")
	}

	private static func title(for migration: StorageMigration) -> String {
		switch migration.sourceVersion {
		case .v1_0:
			MigrationV1.title

		default:
			"Schema migration"
		}
	}
}
