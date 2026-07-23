// swift-tools-version: 6.3

import PackageDescription

let package = Package(
	name: "fxcodex",
	platforms: [
		.macOS(.v14),
	],
	products: [
		.executable(
			name: "fxcodex",
			targets: ["FXCodexCLI"]
		),
	],
	dependencies: [
		.package(
			url: "https://github.com/apple/swift-argument-parser.git",
			.upToNextMajor(from: "1.8.2")
		),
		.package(
			url: "https://github.com/vapor/console-kit.git",
			.upToNextMajor(from: "4.16.0")
		),
		.package(
			url: "https://github.com/pointfreeco/swift-dependencies.git",
			.upToNextMajor(from: "1.14.1")
		),
		.package(
			url: "https://github.com/pointfreeco/swift-case-paths.git",
			.upToNextMajor(from: "1.9.0")
		),
		.package(
			url: "https://github.com/pointfreeco/swift-parsing.git",
			.upToNextMajor(from: "0.15.0")
		),
		.package(
			url: "https://github.com/onmyway133/Promptberry.git",
			.upToNextMajor(from: "1.0.0")
		),
	],
	targets: [
		.executableTarget(
			name: "FXCodexCLI",
			dependencies: [
				.target(
					name: "FXCodexClient",
					condition: nil
				),
				.product(
					name: "ArgumentParser",
					package: "swift-argument-parser"
				),
				.product(
					name: "ConsoleKitTerminal",
					package: "console-kit"
				),
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
				.product(
					name: "Promptberry",
					package: "Promptberry"
				),
			],
			path: "Sources/fxcodex-cli"
		),
		.target(
			name: "FXCodexClient",
			dependencies: [
				.target(
					name: "FXCodexFS",
					condition: nil
				),
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
				.product(
					name: "DependenciesMacros",
					package: "swift-dependencies"
				),
				.product(
					name: "CasePaths",
					package: "swift-case-paths"
				),
				.product(
					name: "Parsing",
					package: "swift-parsing"
				),
			],
			path: "Sources/fxcodex-client"
		),
		.target(
			name: "FXCodexFS",
			dependencies: [],
			path: "Sources/fxcodex-fs"
		),
		.testTarget(
			name: "FXCodexCLITests",
			dependencies: [
				.target(
					name: "FXCodexCLI",
					condition: nil
				),
				.target(
					name: "FXCodexClient",
					condition: nil
				),
				.product(
					name: "Dependencies",
					package: "swift-dependencies"
				),
			],
			path: "Tests/fxcodex-cli-tests"
		),
		.testTarget(
			name: "FXCodexClientTests",
			dependencies: [
				.target(
					name: "FXCodexClient",
					condition: nil
				),
			],
			path: "Tests/fxcodex-client-tests"
		),
	],
	swiftLanguageModes: [.v6]
)
