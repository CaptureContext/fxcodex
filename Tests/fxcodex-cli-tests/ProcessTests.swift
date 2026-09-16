import CustomDump
import Darwin
import Dependencies
import FXCodexClient
import Subprocess
import Testing
@testable
import FXCodexCLI

@Suite("Subprocess execution")
struct ProcessTests {
	@Test("Returns successful and failing exit codes", arguments: [Int32(0), 42], [false, true])
	func exitCode(code: Int32, suppressOutput: Bool) async throws {
		let result: Int32 = try await runProcess(
			.init(
				executable: "/bin/sh",
				arguments: ["-c", "exit \(code)"],
				environment: [:]
			),
			suppressOutput: suppressOutput
		)

		expectNoDifference(result, code)
	}

	@Test("Looks up executables using overridden PATH and preserves arguments and environment")
	func argumentsAndEnvironment() async throws {
		let result: Int32 = try await withDependencies {
			$0._fxcodexEnvironment = .init(values: {
				[
					"PATH": "/does-not-exist",
					"FXCODEX_PROCESS_INHERITED": "inherited value",
					"FXCODEX_PROCESS_OVERRIDE": "old value",
				]
			})
		} operation: {
			try await runProcess(.init(
				executable: "sh",
				arguments: [
					"-c",
					#"[ "$FXCODEX_PROCESS_INHERITED" = 'inherited value' ] && [ "$FXCODEX_PROCESS_OVERRIDE" = 'new value' ] && [ "$#" = 2 ] && [ "$1" = 'spaces and $literal; text' ] && [ "$2" = '' ]"#,
					"fxcodex-process-test",
					"spaces and $literal; text",
					"",
				],
				environment: [
					"PATH": "/bin",
					"FXCODEX_PROCESS_OVERRIDE": "new value",
				]
			))
		}

		expectNoDifference(result, 0)
	}

	@Test("Suppression discards both output streams")
	func suppressedOutput() async throws {
		let result: Int32 = try await runProcess(
			.init(
				executable: "/bin/sh",
				arguments: [
					"-c",
					"test /dev/fd/1 -ef /dev/null && test /dev/fd/2 -ef /dev/null",
				],
				environment: [:]
			),
			suppressOutput: true
		)

		expectNoDifference(result, 0)
	}

	@Test("Returns the terminating signal as a failure status")
	func signalTermination() async throws {
		let result: Int32 = try await runProcess(.init(
			executable: "/bin/sh",
			arguments: ["-c", "kill -TERM $$"],
			environment: [:]
		))

		expectNoDifference(result, SIGTERM)
	}

	@Test("Throws when the executable cannot be launched")
	func missingExecutable() async throws {
		await #expect(throws: SubprocessError.self) {
			try await runProcess(.init(
				executable: "/does-not-exist/fxcodex-process-test",
				arguments: [],
				environment: [:]
			))
		}
	}
}
