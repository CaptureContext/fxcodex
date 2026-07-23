import ArgumentParser
import ConsoleKitTerminal
import Darwin
import Foundation
import FXCodexClient

@MainActor
internal final class TerminalReporter {
	internal let console: Terminal

	internal init(
		assumeYes: Bool = false
	) {
		let console: Terminal = .init()
		console.confirmOverride = assumeYes ? true : nil

		if currentEnvironment()["NO_COLOR"] != nil {
			console.stylizedOutputOverride = false
		}

		self.console = console
	}

	internal func info(_ message: String) {
		self.console.info(message)
	}

	internal func success(_ message: String) {
		self.console.success(message)
	}

	internal func warning(_ message: String) {
		self.console.warning(message)
	}

	internal func confirm(_ message: String) -> Bool {
		self.console.confirm(message.consoleText(.warning))
	}

	internal func ask(_ message: String) -> String {
		self.console.ask(message.consoleText(.info))
	}

	internal func choose<Value: CustomStringConvertible>(
		_ message: String,
		from values: [Value]
	) -> Value {
		self.console.choose(
			message.consoleText(.info),
			from: values
		)
	}
}

internal func replaceProcess(
	with invocation: CommandInvocation
) throws -> Never {
	for (key, value) in invocation.environment {
		guard setenv(key, value, 1) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
	}

	let argumentStrings: [String] = [invocation.executable] + invocation.arguments
	var arguments: [UnsafeMutablePointer<CChar>?] = argumentStrings.map { argument in
		strdup(argument)
	}

	arguments.append(nil)

	defer {
		for argument in arguments where argument != nil {
			free(argument)
		}
	}

	execvp(invocation.executable, &arguments)

	throw POSIXError(.init(rawValue: errno) ?? .ENOENT)
}

internal func runProcess(
	_ invocation: CommandInvocation,
	suppressOutput: Bool = false
) throws -> Int32 {
	let process: Process = .init()
	process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
	process.arguments = [invocation.executable] + invocation.arguments
	process.environment = currentEnvironment().merging(
		invocation.environment,
		uniquingKeysWith: { _, newValue in newValue }
	)

	if suppressOutput {
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
	}

	try process.run()
	process.waitUntilExit()

	return process.terminationStatus
}

internal func forwardedArguments(from arguments: [String]) -> [String] {
	guard arguments.first == "--" else { return arguments }
	return .init(arguments.dropFirst())
}

extension Array where Element == String {
	internal func uniqued() -> [String] {
		var values: Set<String> = []
		return self.filter { values.insert($0).inserted }
	}

	internal var workspaceDescription: String {
		if self.count == 1 {
			return "workspace '\(self[0])'"
		}
		return "workspaces \(self.map { "'\($0)'" }.joined(separator: ", "))"
	}
}

internal func currentExecutableURL() -> URL {
	let path: String = CommandLine.arguments[0]
	let url: URL = URL(fileURLWithPath: path)

	if url.path.hasPrefix("/") {
		return url.resolvingSymlinksInPath()
	}

	return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
	.appending(path: path)
	.resolvingSymlinksInPath()
}

internal func isHomebrewManagedExecutable(_ executableURL: URL) -> Bool {
	let components: [String] = executableURL.standardizedFileURL
		.resolvingSymlinksInPath()
		.pathComponents

	guard let cellarIndex = components.firstIndex(of: "Cellar") else { return false }

	return components.indices.contains(cellarIndex + 1)
		&& components[cellarIndex + 1] == "fxcodex"
}

internal func machineOutputRequested(
	_ localValue: Bool?
) -> Bool {
	localValue ?? globalMachineOutputRequested()
}

internal func globalMachineOutputRequested(
	arguments: [String] = .init(CommandLine.arguments.dropFirst()),
	environment: [String: String]? = nil
) -> Bool {
	let environment = environment ?? currentEnvironment()
	let passthroughCommandIndex: Int? = arguments.firstIndex { argument in
		argument == "cli" || argument == "exec"
	}
	let relevantArguments: ArraySlice<String> = passthroughCommandIndex.map {
		arguments[..<$0]
	}
	?? arguments[...]

	var argumentValue: Bool?

	for argument in relevantArguments {
		switch argument {
		case "--json":
			argumentValue = true

		case "--no-json":
			argumentValue = false

		default:
			break
		}
	}

	if let argumentValue {
		return argumentValue
	}

	return (try? environmentSwitch(
		named: "FXCODEX_JSON",
		in: environment
	))
	?? false
}

internal func environmentSwitch(
	named name: String,
	in environment: [String: String]? = nil
) throws -> Bool? {
	let environment = environment ?? currentEnvironment()
	guard let value = environment[name], !value.isEmpty else { return nil }

	switch value {
	case "1":
		return true

	case "-1", "0":
		return false

	default:
		throw ValidationError(
			"Environment variable \(name) must be 1, -1, or unset."
		)
	}
}

internal func rejectMachineOutput(
	for commandName: String
) throws {
	guard !globalMachineOutputRequested() else {
		throw ValidationError("--json is not supported by the \(commandName) command.")
	}
}

internal func encodedJSON<Value: Encodable>(
	_ value: Value
) throws -> Data {
	let encoder: JSONEncoder = FXCodexJSONCoding.encoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
	return try encoder.encode(value)
}

internal func printMachineResponse<Value: Encodable>(
	_ value: Value
) throws {
	try writeJSON(
		MachineResponse(data: value),
		to: .standardOutput
	)
}

internal func printMachineError(
	_ error: any Error
) throws {
	try writeJSON(
		MachineErrorResponse(error: error),
		to: .standardError
	)
}

internal func printMachineWarning(
	_ warning: FXCodexWarning
) throws {
	try writeJSON(
		MachineWarningResponse(warning: warning),
		to: .standardError
	)
}

private func writeJSON<Value: Encodable>(
	_ value: Value,
	to fileHandle: FileHandle
) throws {
	var data: Data = try encodedJSON(value)
	data.append(contentsOf: [0x0A])

	try fileHandle.write(contentsOf: data)
}
