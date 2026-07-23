import ArgumentParser
import Dependencies
import Foundation
import FXCodexClient
import Testing
@testable
import FXCodexCLI

@Suite("Machine response")
struct MachineResponseTests {
	@Test("Success responses use the versioned envelope")
	func success() async throws {
		let data: Data = try encodedJSON(MachineResponse(
			data: VersionOutput(version: "1.2.3")
		))
		let object: [String: Any] = try #require(
			JSONSerialization.jsonObject(with: data) as? [String: Any]
		)
		let output: [String: Any] = try #require(object["data"] as? [String: Any])

		#expect(object["api_version"] as? Int == 1)
		#expect(object["ok"] as? Bool == true)
		#expect(output["version"] as? String == "1.2.3")
	}

	@Test("Encoding failure fallback uses the machine JSON contract")
	func encodingFailureFallback() throws {
		let data: Data = .init(AppCommand.machineEncodingFailureResponse.utf8)
		let object: [String: Any] = try #require(
			JSONSerialization.jsonObject(with: data) as? [String: Any]
		)
		let error: [String: Any] = try #require(
			object["error"] as? [String: Any]
		)

		#expect(object["api_version"] as? Int == 1)
		#expect(object["apiVersion"] == nil)
		#expect(object["ok"] as? Bool == false)
		#expect(error["code"] as? String == "encoding_failed")
	}

	@Test("Client errors expose stable codes")
	func clientError() async throws {
		let response: MachineErrorResponse = .init(
			error: FXCodexError.workspaceNotFound("work")
		)

		#expect(response.apiVersion == 1)
		#expect(!response.ok)
		#expect(response.error.code == "workspace_not_found")
		#expect(response.error.message == "Workspace 'work' does not exist.")
	}

	@Test("Validation errors use the invalid arguments code")
	func validationError() async throws {
		let response: MachineErrorResponse = .init(
			error: ValidationError("A workspace name is required.")
		)

		#expect(response.error.code == "invalid_arguments")
		#expect(response.error.message == "A workspace name is required.")
	}

	@Test("Passthrough JSON arguments do not enable machine output")
	func passthroughArguments() async throws {
		#expect(globalMachineOutputRequested(
			arguments: ["--json", "cli"],
			environment: [:]
		))
		#expect(!globalMachineOutputRequested(
			arguments: ["cli", "--json"],
			environment: [:]
		))
		#expect(!globalMachineOutputRequested(
			arguments: ["exec", "--", "--json"],
			environment: [:]
		))
		#expect(globalMachineOutputRequested(
			arguments: ["status", "--json"],
			environment: [:]
		))
	}

	@Test("Environment enables JSON unless an argument disables it")
	func environmentJSON() async throws {
		let environment: [String: String] = ["FXCODEX_JSON": "1"]

		#expect(globalMachineOutputRequested(
			arguments: ["status"],
			environment: environment
		))
		#expect(!globalMachineOutputRequested(
			arguments: ["--no-json", "status"],
			environment: environment
		))
	}

	@Test("Commands read environment through the injected client")
	func injectedEnvironment() {
		withDependencies {
			$0._fxcodexEnvironment = .init(values: {
				["FXCODEX_JSON": "1"]
			})
		} operation: {
			#expect(globalMachineOutputRequested(arguments: ["status"]))
			#expect(!globalMachineOutputRequested(arguments: ["--no-json", "status"]))
		}
	}

	@Test("Warnings use a structured machine response")
	func warningResponse() async throws {
		let data: Data = try encodedJSON(MachineWarningResponse(
			warning: .init(
				code: "application_name_conflict",
				message: "Both application names are present."
			)
		))
		let object: [String: Any] = try #require(
			JSONSerialization.jsonObject(with: data) as? [String: Any]
		)
		let warning: [String: Any] = try #require(
			object["warning"] as? [String: Any]
		)

		#expect(object["api_version"] as? Int == 1)
		#expect(warning["code"] as? String == "application_name_conflict")
	}

	@Test("Nested output properties use lower snake case")
	func lowerSnakeCase() async throws {
		let data: Data = try encodedJSON(MachineResponse(
			data: OpenWorkspaceOutput(workspaceName: "work", processID: 42)
		))
		let object: [String: Any] = try #require(
			JSONSerialization.jsonObject(with: data) as? [String: Any]
		)
		let output: [String: Any] = try #require(object["data"] as? [String: Any])

		#expect(output["workspace_name"] as? String == "work")
		#expect(output["process_id"] as? Int == 42)
		#expect(output["workspaceName"] == nil)
		#expect(output["processID"] == nil)
	}

	@Test("Every client error has a stable machine code")
	func clientErrorCodes() async throws {
		let cases: [(FXCodexError, String)] = [
			(.applicationNotFound, "application_not_found"),
			(.applicationBundleMismatch(URL(fileURLWithPath: "/Applications/ChatGPT.app")), "application_bundle_mismatch"),
			(.ambiguousApplicationInstances([42]), "ambiguous_application_instances"),
			(.codexExecutableNotFound, "codex_executable_not_found"),
			(.homebrewNotFound, "homebrew_not_found"),
			(.homebrewManagedUpdate, "homebrew_managed_update"),
			(.integrationAttributeNotFound("raycast.icon"), "integration_attribute_not_found"),
			(.invalidAttributePath("icons.(unknown)"), "invalid_attribute_path"),
			(.invalidStorage("missing metadata"), "invalid_storage"),
			(.invalidWorkspaceName("Work"), "invalid_workspace_name"),
			(.primaryWorkspaceMutation, "primary_workspace_mutation"),
			(.raycastBetaUnsupportedPlatform, "raycast_beta_unsupported_platform"),
			(.raycastScriptCommandDirectoryMissing, "raycast_script_command_directory_missing"),
			(.supportDirectoryInvalid(URL(fileURLWithPath: "/")), "support_directory_invalid"),
			(.updateArchitectureUnsupported, "update_architecture_unsupported"),
			(.updateAssetMissing("fxcodex"), "update_asset_missing"),
			(.updateChecksumInvalid, "update_checksum_invalid"),
			(.updateChecksumMismatch, "update_checksum_mismatch"),
			(.updateExecutableInvalid(URL(fileURLWithPath: "/tmp/fxcodex")), "update_executable_invalid"),
			(.updateRequestFailed(503), "update_request_failed"),
			(.unsupportedSchemaVersion(.init(major: 3, minor: 0)), "unsupported_schema_version"),
			(.workspaceAlreadyExists("work"), "workspace_already_exists"),
			(.workspaceIsRunning("work"), "workspace_is_running"),
			(.workspaceNotFound("work"), "workspace_not_found"),
		]

		for (error, code) in cases {
			#expect(error.code == code)
		}
	}

	@Test("Extension-facing commands accept local machine output flags")
	func commandFlags() async throws {
		let status: AppCommand.StatusCommand = try .parse(["--json"])
		let list: AppCommand.WorkspaceCommand.List = try .parse(["--json"])
		let rename: AppCommand.WorkspaceCommand.Rename = try .parse([
			"work",
			"office",
			"--json",
		])
		let use: AppCommand.WorkspaceCommand.Use = try .parse([
			"work",
			"--json",
		])
		let open: AppCommand.OpenCommand = try .parse([
			"work",
			"--json",
		])
		let openByID: AppCommand.OpenCommand = try .parse([
			"--workspace-id",
			"00000000-0000-0000-0000-000000000001",
			"--json",
		])
		let getAttribute: AppCommand.IntegrationsCommand.Attributes.Get = try .parse([
			"raycast",
			"--path",
			"workspaces.(keys)",
			"--json",
		])
		let installRaycast: AppCommand.IntegrationsCommand.Raycast.Install = try .parse([
			"script-command",
			"--directory",
			"/tmp/raycast",
			"--json",
		])
		let raycast: AppCommand.IntegrationsCommand.Raycast.Status = try .parse(["--json"])
		let version: VersionCommand = try .parse(["--json"])

		#expect(status.json == true)
		#expect(list.json == true)
		#expect(rename.json == true)
		#expect(use.json == true)
		#expect(open.json == true)
		#expect(openByID.workspaceID == "00000000-0000-0000-0000-000000000001")
		#expect(openByID.json == true)
		#expect(getAttribute.integration == "raycast")
		#expect(getAttribute.path == "workspaces.(keys)")
		#expect(getAttribute.json == true)
		#expect(installRaycast.component == .scriptCommand)
		#expect(installRaycast.json == true)
		#expect(raycast.json == true)
		#expect(version.json == true)
	}
}
