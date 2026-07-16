import Foundation

public enum RaycastApplicationInstallation: Equatable, Sendable {
	case alreadyInstalled(URL)
	case command(CommandInvocation)
	case externalDownload(URL)
}
