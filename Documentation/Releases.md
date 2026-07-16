# Release contract

The self-updater reads releases from `CaptureContext/fxcodex` using GitHub's
Releases API. Release tags must be plain semantic versions without a `v`
prefix, for example `1.2.3`. The release workflow creates the tag only after
all artifacts pass validation. Its version must match `AppCommand.version`
exactly.

Each release must contain the dependency snapshot used by every release build,
raw architecture-specific and universal executables, and a SHA-256 checksum
file for each executable:

```text
Package.resolved
fxcodex-aarch64-apple-darwin
fxcodex-aarch64-apple-darwin.sha256
fxcodex-x86_64-apple-darwin
fxcodex-x86_64-apple-darwin.sha256
fxcodex-universal-apple-darwin
fxcodex-universal-apple-darwin.sha256
```

The checksum file starts with the lowercase or uppercase hexadecimal SHA-256
digest. Additional filename text after whitespace is allowed.

Run the `Release` workflow manually from the `main` branch and enter the release
version. The workflow pins every job to that commit, resolves dependencies
once, requires both architecture jobs to use that exact `Package.resolved`,
tests and builds natively on Apple silicon and Intel runners, and combines those
exact binaries into the universal executable. The protected `release`
environment then provides the Developer ID and App Store Connect credentials
used to sign and notarize all three executables. Checksums are generated after
signing and verified. Only after every check succeeds does the workflow create
the tag and publish the GitHub Release together. Before running the workflow:

1. Set `AppCommand.version` to the release version.
2. Build and test both architectures.
3. Commit and push the release-ready state to `main`.

The release job signs every executable with the hardened runtime and a secure
timestamp before submitting them together to Apple's notary service. Raw
command-line executables cannot carry a stapled ticket, so Gatekeeper retrieves
their notarization tickets online using the signed code hashes. The workflow
verifies the signatures and online tickets before publishing any assets.

The `release` GitHub environment must define these environment secrets:

- `DEVELOPER_ID_CERTIFICATE_P12_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `APP_STORE_CONNECT_API_KEY_P8_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

The certificate archive must contain a Developer ID Application identity. The
API key must have permission to submit software to Apple's notarization service.
The environment deployment policy must allow the `main` branch.

`Package.resolved` remains ignored during normal development. The release
workflow generates it in a dedicated job, shares it with both architecture
jobs, and verifies it with `swift package resolve --force-resolved-versions`
before testing or building. It then publishes the same file as a release asset.
This makes the dependency graph traceable and consistent across release
artifacts without committing the local resolver state.

GitHub's automatic source archives do not contain this ignored file. To
reproduce a release, download its source archive and `Package.resolved`, place
the resolved file at the package root, and run:

```sh
swift package resolve --force-resolved-versions
make test
make release
```

## Universal executable

The Raycast extension embeds a universal executable instead of either
architecture-specific updater artifact. Run:

```sh
make universal
```

This delegates to `Scripts/build-universal.sh`, builds both `arm64` and
`x86_64` slices with a macOS 14 deployment target, and writes these files:

```text
dist/fxcodex-universal-apple-darwin
dist/fxcodex-universal-apple-darwin.sha256
```

Override `OUTPUT_PATH` when invoking the script directly to place the binary
elsewhere, including the Raycast extension's `assets/bin` directory. The
universal artifact is the default choice for manual installation and extension
embedding. The self-updater preserves universal installations by comparing the
installed executable with the current release's universal checksum. A match
selects the next universal artifact; otherwise it selects the artifact for the
running architecture.

Draft releases are ignored. The minor and major channels ignore prereleases;
the latest channel includes them. The updater downloads the selected binary and
checksum concurrently, verifies SHA-256, preserves executable permissions, and
atomically replaces the running executable's file for subsequent invocations.
