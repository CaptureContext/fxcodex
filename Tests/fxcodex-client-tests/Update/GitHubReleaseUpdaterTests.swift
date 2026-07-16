import CryptoKit
import Foundation
import Testing
@testable import FXCodexClient

@Suite("GitHub release updater", .serialized)
struct GitHubReleaseUpdaterTests {
	@Test("Selects releases using constraints anchored at an optional minimum version")
	func selection() async throws {
		let currentVersion: SemanticVersion = try #require(.init("1.2.3"))
		let releases: [GitHubReleaseUpdater.Release] = [
			Self.release("v1.2.4"),
			Self.release("v1.3.0"),
			Self.release("v1.3.5"),
			Self.release("v1.4.0"),
			Self.release("v2.0.0"),
			Self.release("v2.1.0-beta.1", prerelease: true),
			Self.release("v3.0.0", draft: true),
		]

		#expect(Self.selectedVersion(
			releases,
			currentVersion,
			.patch,
			nil
		) == "1.2.4")
		#expect(Self.selectedVersion(
			releases,
			currentVersion,
			.minor,
			nil
		) == "1.4.0")
		#expect(Self.selectedVersion(
			releases,
			currentVersion,
			.major,
			nil
		) == "2.0.0")
		#expect(Self.selectedVersion(
			releases,
			currentVersion,
			.latest,
			nil
		) == "2.1.0-beta.1")
		#expect(Self.selectedVersion(
			releases,
			currentVersion,
			.patch,
			try #require(.init("1.3.0"))
		) == "1.3.5")
		#expect(Self.selectedVersion(
			releases,
			currentVersion,
			.minor,
			try #require(.init("1.3.0"))
		) == "1.4.0")
		#expect(Self.selectedVersion(
			releases,
			currentVersion,
			.major,
			try #require(.init("2.0.0"))
		) == "2.0.0")
	}

	@Test("Downloads, verifies, and replaces only a temporary executable fixture")
	func replacement() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }
		let artifact: Data = .init("#!/bin/sh\necho updated\n".utf8)
		let checksum: String = Self.checksum(artifact)
		let releasesURL: URL = try #require(URL(
			string: "https://api.github.com/repos/maximkrouk/fxcodex/releases?per_page=100"
		))
		let currentReleaseURL: URL = try #require(URL(
			string: "https://api.github.com/repos/maximkrouk/fxcodex/releases/tags/0.1.0"
		))
		let artifactURL: URL = try #require(URL(string: "https://example.com/fxcodex"))
		let checksumURL: URL = try #require(URL(string: "https://example.com/fxcodex.sha256"))
		let currentUniversalChecksumURL: URL = try #require(URL(
			string: "https://example.com/fxcodex-universal-current.sha256"
		))
		let artifactName: String
		#if arch(arm64)
		artifactName = "fxcodex-aarch64-apple-darwin"
		#else
		artifactName = "fxcodex-x86_64-apple-darwin"
		#endif
		let releaseJSON: String = """
		[
		  {
		    "tag_name": "0.2.0",
		    "draft": false,
		    "prerelease": false,
		    "assets": [
		      {"name": "\(artifactName)", "browser_download_url": "\(artifactURL.absoluteString)"},
		      {"name": "\(artifactName).sha256", "browser_download_url": "\(checksumURL.absoluteString)"}
		    ]
		  }
		]
		"""
		let currentReleaseJSON: String = """
		{
		  "tag_name": "0.1.0",
		  "draft": false,
		  "prerelease": false,
		  "assets": [
		    {
		      "name": "fxcodex-universal-apple-darwin.sha256",
		      "browser_download_url": "\(currentUniversalChecksumURL.absoluteString)"
		    }
		  ]
		}
		"""
		URLProtocolStub.responses = [
			releasesURL: .init(releaseJSON.utf8),
			currentReleaseURL: .init(currentReleaseJSON.utf8),
			artifactURL: artifact,
			checksumURL: .init("\(checksum)  \(artifactName)\n".utf8),
			currentUniversalChecksumURL: .init("\(String(repeating: "0", count: 64))\n".utf8),
		]
		defer { URLProtocolStub.responses = [:] }
		let configuration: URLSessionConfiguration = .ephemeral
		configuration.protocolClasses = [URLProtocolStub.self]
		let updater: GitHubReleaseUpdater = .init(
			repository: "maximkrouk/fxcodex",
			fileManager: .default,
			session: .init(configuration: configuration)
		)

		let result: UpdateResult = try await updater.update(
			currentVersion: .init(major: 0, minor: 1, patch: 0),
			channel: .minor,
			minimumVersion: nil,
			executableURL: fixture.executableURL
		)

		#expect(result.outcome == .updated)
		#expect(result.version == .init(major: 0, minor: 2, patch: 0))
		#expect(try Data(contentsOf: fixture.executableURL) == artifact)
	}

	@Test("Preserves a universal installation across updates")
	func universalReplacement() async throws {
		let fixture: ClientTestFixture = try .init()
		defer { fixture.remove() }
		let currentArtifact: Data = try .init(contentsOf: fixture.executableURL)
		let currentChecksum: String = Self.checksum(currentArtifact)
		let updatedArtifact: Data = .init("updated universal executable".utf8)
		let updatedChecksum: String = Self.checksum(updatedArtifact)
		let releasesURL: URL = try #require(URL(
			string: "https://api.github.com/repos/maximkrouk/fxcodex/releases?per_page=100"
		))
		let currentReleaseURL: URL = try #require(URL(
			string: "https://api.github.com/repos/maximkrouk/fxcodex/releases/tags/0.1.0"
		))
		let artifactURL: URL = try #require(URL(
			string: "https://example.com/fxcodex-universal"
		))
		let checksumURL: URL = try #require(URL(
			string: "https://example.com/fxcodex-universal.sha256"
		))
		let currentChecksumURL: URL = try #require(URL(
			string: "https://example.com/fxcodex-universal-current.sha256"
		))
		let releaseJSON: String = """
		[
		  {
		    "tag_name": "0.2.0",
		    "draft": false,
		    "prerelease": false,
		    "assets": [
		      {
		        "name": "fxcodex-universal-apple-darwin",
		        "browser_download_url": "\(artifactURL.absoluteString)"
		      },
		      {
		        "name": "fxcodex-universal-apple-darwin.sha256",
		        "browser_download_url": "\(checksumURL.absoluteString)"
		      }
		    ]
		  }
		]
		"""
		let currentReleaseJSON: String = """
		{
		  "tag_name": "0.1.0",
		  "draft": false,
		  "prerelease": false,
		  "assets": [
		    {
		      "name": "fxcodex-universal-apple-darwin.sha256",
		      "browser_download_url": "\(currentChecksumURL.absoluteString)"
		    }
		  ]
		}
		"""
		URLProtocolStub.responses = [
			releasesURL: .init(releaseJSON.utf8),
			currentReleaseURL: .init(currentReleaseJSON.utf8),
			artifactURL: updatedArtifact,
			checksumURL: .init("\(updatedChecksum)\n".utf8),
			currentChecksumURL: .init("\(currentChecksum)\n".utf8),
		]
		defer { URLProtocolStub.responses = [:] }
		let configuration: URLSessionConfiguration = .ephemeral
		configuration.protocolClasses = [URLProtocolStub.self]
		let updater: GitHubReleaseUpdater = .init(
			repository: "maximkrouk/fxcodex",
			fileManager: .default,
			session: .init(configuration: configuration)
		)

		let result: UpdateResult = try await updater.update(
			currentVersion: .init(major: 0, minor: 1, patch: 0),
			channel: .minor,
			minimumVersion: nil,
			executableURL: fixture.executableURL
		)

		#expect(result.outcome == .updated)
		#expect(result.version == .init(major: 0, minor: 2, patch: 0))
		#expect(try Data(contentsOf: fixture.executableURL) == updatedArtifact)
	}

	@Test("Rejects malformed and mismatched checksums")
	func checksumValidation() async throws {
		let artifact: Data = .init("artifact".utf8)

		#expect(throws: FXCodexError.updateChecksumInvalid) {
			try GitHubReleaseUpdater.validateChecksum(
				.init("not-a-checksum".utf8),
				artifact: artifact
			)
		}
		#expect(throws: FXCodexError.updateChecksumMismatch) {
			try GitHubReleaseUpdater.validateChecksum(
				.init(String(repeating: "0", count: 64).utf8),
				artifact: artifact
			)
		}
	}
}

extension GitHubReleaseUpdaterTests {
	private static func checksum(_ data: Data) -> String {
		SHA256.hash(data: data)
		.map { String(format: "%02x", $0) }
		.joined()
	}

	private static func release(
		_ tagName: String,
		draft: Bool = false,
		prerelease: Bool = false
	) -> GitHubReleaseUpdater.Release {
		.init(
			tagName: tagName,
			draft: draft,
			prerelease: prerelease,
			assets: []
		)
	}

	private static func selectedVersion(
		_ releases: [GitHubReleaseUpdater.Release],
		_ currentVersion: SemanticVersion,
		_ channel: UpdateChannel,
		_ minimumVersion: SemanticVersion?
	) -> String? {
		GitHubReleaseUpdater.selectRelease(
			from: releases,
			currentVersion: currentVersion,
			channel: channel,
			minimumVersion: minimumVersion
		)?.version?.description
	}
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
	nonisolated(unsafe) static var responses: [URL: Data] = [:]

	override class func canInit(with request: URLRequest) -> Bool {
		true
	}

	override class func canonicalRequest(for request: URLRequest) -> URLRequest {
		request
	}

	override func startLoading() {
		guard let url = self.request.url, let data = Self.responses[url] else {
			self.client?.urlProtocol(
				self,
				didFailWithError: URLError(.resourceUnavailable)
			)
			return
		}
		let response: HTTPURLResponse = .init(
			url: url,
			statusCode: 200,
			httpVersion: "HTTP/1.1",
			headerFields: nil
		)!
		self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
		self.client?.urlProtocol(self, didLoad: data)
		self.client?.urlProtocolDidFinishLoading(self)
	}

	override func stopLoading() {}
}
