import Dependencies
import Foundation
import Testing
@_spi(Internals)
@testable
import FXCodexClient

@Suite("Integration attributes storage")
struct IntegrationAttributesStorageTests {
	@Test("Mutates nested attributes by stable workspace ID")
	func lifecycle() async throws {
		let fixture = try ClientTestFixture()
		defer { fixture.remove() }

		try withDependencies {
			$0.context = .live
			$0._fxcodexPaths = .init(rootURL: fixture.rootURL)
		} operation: {
			let workspaces = WorkspacesStorage(fileManager: .default)
			let workspace = try workspaces.createWorkspace(named: "work")
			let attributes = IntegrationAttributesStorage(fileManager: .default)
			let iconPath = try IntegrationAttributePath("workspaces.[key: \(workspace.id.rawValue)].icon")
			let icon: CodableValue = .dictionary([
				"type": .string("raycast"),
				"value": .string("Folder"),
			])

			try attributes.setValue(integration: "raycast", path: iconPath, value: icon)
			#expect(try attributes.value(integration: "raycast", path: iconPath) == icon)
			#expect(try attributes.value(
				integration: "raycast",
				path: .init("workspaces.(keys)")
			) == .array([.string(workspace.id.rawValue)]))

			let renamed = try workspaces.renameWorkspace(id: workspace.id, to: "renamed")
			#expect(renamed.id == workspace.id)
			#expect(try attributes.value(integration: "raycast", path: iconPath) == icon)

			#expect(throws: FXCodexError.invalidAttributePath("workspaces.(keys)")) {
				try attributes.setValue(
					integration: "raycast",
					path: .init("workspaces.(keys)"),
					value: .array([])
				)
			}

			try attributes.removeValue(integration: "raycast", path: iconPath)
			#expect(throws: FXCodexError.integrationAttributeNotFound("raycast.\(iconPath.rawValue)")) {
				try attributes.value(integration: "raycast", path: iconPath)
			}
		}
	}
}
