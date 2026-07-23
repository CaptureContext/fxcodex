import CryptoKit
import Foundation

final class GitHubReleaseUpdater: @unchecked Sendable {
	struct Release: Decodable, Equatable, Sendable {
		struct Asset: Decodable, Equatable, Sendable {
			let name: String
			let browserDownloadURL: URL

			private enum CodingKeys: String, CodingKey {
				case name
				case browserDownloadURL = "browser_download_url"
			}
		}

		let tagName: String
		let draft: Bool
		let prerelease: Bool
		let assets: [Asset]

		var version: SemanticVersion? {
			.init(self.tagName)
		}

		private enum CodingKeys: String, CodingKey {
			case tagName = "tag_name"
			case draft
			case prerelease
			case assets
		}
	}

	private let decoder: JSONDecoder
	private let fileManager: FileManager
	private let releaseTagsURL: URL
	private let releasesURL: URL
	private let session: URLSession

	init(
		repository: String,
		fileManager: FileManager,
		session: URLSession
	) {
		self.decoder = .init()
		self.fileManager = fileManager
		self.releaseTagsURL = URL(
			string: "https://api.github.com/repos/\(repository)/releases/tags"
		)!
		self.releasesURL = URL(
			string: "https://api.github.com/repos/\(repository)/releases?per_page=100"
		)!
		self.session = session
	}

	func update(
		currentVersion: SemanticVersion,
		channel: UpdateChannel,
		minimumVersion: SemanticVersion?,
		executableURL: URL
	) async throws -> UpdateResult {
		let releases: [Release] = try await self.releases()

		guard
			let release = Self.selectRelease(
				from: releases,
				currentVersion: currentVersion,
				channel: channel,
				minimumVersion: minimumVersion
			),
			let version = release.version
		else {
			return .init(
				outcome: .alreadyCurrent,
				previousVersion: currentVersion,
				version: currentVersion
			)
		}

		let artifactName: String = try await self.artifactName(
			currentVersion: currentVersion,
			executableURL: executableURL
		)

		guard let artifact = release.assets.first(where: { $0.name == artifactName })
		else { throw FXCodexError.updateAssetMissing(artifactName) }

		let checksumName: String = "\(artifactName).sha256"

		guard let checksum = release.assets.first(where: { $0.name == checksumName })
		else { throw FXCodexError.updateAssetMissing(checksumName) }

		async let artifactData = self.download(artifact.browserDownloadURL)
		async let checksumData = self.download(checksum.browserDownloadURL)
		let (downloadedArtifact, downloadedChecksum) = try await (
			artifactData,
			checksumData
		)
		try Self.validateChecksum(
			downloadedChecksum,
			artifact: downloadedArtifact
		)
		try self.replaceExecutable(
			at: executableURL,
			with: downloadedArtifact
		)

		return .init(
			outcome: .updated,
			previousVersion: currentVersion,
			version: version
		)
	}

	static func selectRelease(
		from releases: [Release],
		currentVersion: SemanticVersion,
		channel: UpdateChannel,
		minimumVersion: SemanticVersion?
	) -> Release? {
		let constraintVersion: SemanticVersion = minimumVersion ?? currentVersion
		return releases
		.filter { release in
			guard !release.draft, let version = release.version else { return false }
			guard version > currentVersion else { return false }
			guard minimumVersion.map({ version >= $0 }) ?? true else { return false }

			switch channel {
			case .patch:
				return !release.prerelease
				&& !version.isPrerelease
				&& version.major == constraintVersion.major
				&& version.minor == constraintVersion.minor

			case .minor:
				return !release.prerelease
				&& !version.isPrerelease
				&& version.major == constraintVersion.major

			case .major:
				return !release.prerelease && !version.isPrerelease

			case .latest:
				return true
			}
		}
		.max { lhs, rhs in
			guard let lhsVersion = lhs.version, let rhsVersion = rhs.version else { return false }
			return lhsVersion < rhsVersion
		}
	}
}

extension GitHubReleaseUpdater {
	private func releases() async throws -> [Release] {
		let data: Data = try await self.data(for: self.request(self.releasesURL))
		return try self.decoder.decode([Release].self, from: data)
	}

	private func release(tag: String) async throws -> Release {
		let url: URL = self.releaseTagsURL.appending(
			path: tag,
			directoryHint: .notDirectory
		)
		let data: Data = try await self.data(for: self.request(url))
		return try self.decoder.decode(Release.self, from: data)
	}

	private func request(_ url: URL) -> URLRequest {
		var request: URLRequest = .init(url: url)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
		request.setValue("fxcodex", forHTTPHeaderField: "User-Agent")
		return request
	}

	private func download(_ url: URL) async throws -> Data {
		var request: URLRequest = .init(url: url)
		request.setValue("fxcodex", forHTTPHeaderField: "User-Agent")
		return try await self.data(for: request)
	}

	private func data(for request: URLRequest) async throws -> Data {
		let (data, response) = try await self.session.data(for: request)

		guard
			let response = response as? HTTPURLResponse,
			(200..<300).contains(response.statusCode)
		else {
			throw FXCodexError.updateRequestFailed(
				(response as? HTTPURLResponse)?.statusCode ?? 0
			)
		}

		return data
	}

	private func replaceExecutable(
		at executableURL: URL,
		with data: Data
	) throws {
		let executableURL: URL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
		let values = try executableURL.resourceValues(forKeys: [.isRegularFileKey])

		guard values.isRegularFile == true
		else { throw FXCodexError.updateExecutableInvalid(executableURL) }

		let attributes = try self.fileManager.attributesOfItem(atPath: executableURL.path)
		let permissions: NSNumber = attributes[.posixPermissions] as? NSNumber ?? 0o755
		let temporaryURL: URL = executableURL.deletingLastPathComponent().appending(
			path: ".fxcodex-update-\(UUID().uuidString)",
			directoryHint: .notDirectory
		)
		defer { try? self.fileManager.removeItem(at: temporaryURL) }

		try data.write(to: temporaryURL, options: [.atomic])
		try self.fileManager.setAttributes(
			[.posixPermissions: permissions],
			ofItemAtPath: temporaryURL.path
		)
		_ = try self.fileManager.replaceItemAt(
			executableURL,
			withItemAt: temporaryURL
		)
	}

	private func artifactName(
		currentVersion: SemanticVersion,
		executableURL: URL
	) async throws -> String {
		let release: Release = try await self.release(tag: currentVersion.description)
		let checksumName: String = "\(Self.universalArtifactName).sha256"

		guard let checksum = release.assets.first(where: { $0.name == checksumName })
		else { throw FXCodexError.updateAssetMissing(checksumName) }

		let checksumData: Data = try await self.download(checksum.browserDownloadURL)
		let executableURL: URL = executableURL.standardizedFileURL.resolvingSymlinksInPath()
		let values = try executableURL.resourceValues(forKeys: [.isRegularFileKey])

		guard values.isRegularFile == true
		else { throw FXCodexError.updateExecutableInvalid(executableURL) }

		let executableData: Data = try .init(contentsOf: executableURL)
		if try Self.checksumMatches(checksumData, artifact: executableData) {
			return Self.universalArtifactName
		}
		return try Self.nativeArtifactName()
	}

	private static let universalArtifactName: String =
		"fxcodex-universal-apple-darwin"

	private static func nativeArtifactName() throws -> String {
		#if arch(arm64)
		"fxcodex-aarch64-apple-darwin"
		#elseif arch(x86_64)
		"fxcodex-x86_64-apple-darwin"
		#else
		throw FXCodexError.updateArchitectureUnsupported
		#endif
	}

	static func validateChecksum(
		_ checksumData: Data,
		artifact: Data
	) throws {
		guard try Self.checksumMatches(checksumData, artifact: artifact)
		else { throw FXCodexError.updateChecksumMismatch }
	}

	private static func checksumMatches(
		_ checksumData: Data,
		artifact: Data
	) throws -> Bool {
		guard
			let checksumContents = String(data: checksumData, encoding: .utf8),
			let expectedChecksum = checksumContents.split(whereSeparator: \.isWhitespace).first
		else { throw FXCodexError.updateChecksumInvalid }

		let normalizedChecksum: String = expectedChecksum.lowercased()

		guard
			normalizedChecksum.count == 64,
			normalizedChecksum.allSatisfy({ $0.isHexDigit })
		else { throw FXCodexError.updateChecksumInvalid }

		let actualChecksum: String = SHA256.hash(data: artifact)
		.map { String(format: "%02x", $0) }
		.joined()
		return actualChecksum == normalizedChecksum
	}
}
