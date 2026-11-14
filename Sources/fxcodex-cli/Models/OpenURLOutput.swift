import Foundation
import FXCodexClient

internal struct OpenURLOutput: Encodable {
	internal let workspaceName: String
	internal let workspaceID: WorkspaceID
	internal let processID: Int32
	internal let delivery: URLDelivery.Method

	internal init(
		_ delivery: URLDelivery
	) {
		self.workspaceName = delivery.workspace.name
		self.workspaceID = delivery.workspace.id
		self.processID = delivery.processID
		self.delivery = delivery.method
	}
}
