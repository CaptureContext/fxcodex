# fxcodex

**Independent workspaces and practical extras for Codex on macOS.**

`fxcodex` is an unofficial companion CLI for developers who want to keep
personal and work Codex accounts available side by side. It gives each managed
workspace an isolated Codex home and desktop-app data directory, carries the
same isolation into the Codex CLI, and can optionally preserve the Codex app
name.

- Stay signed in to multiple Codex accounts at the same time.
- Open or focus an independent desktop-app instance for each account.
- Run `codex` and `codex exec` with the matching isolated profile.
- Manage workspaces from the terminal or generated Raycast Script Commands.
- Optionally rename `ChatGPT.app` to `Codex.app`.
- Update the `fxcodex` executable from verified GitHub Release artifacts.

`fxcodex` is not affiliated with or endorsed by OpenAI or Raycast.

## How it works

A **workspace** is an isolated Codex profile, not a source-code project or
repository.

The built-in **`primary` workspace** represents the Codex setup already on the
Mac and continues to use Codex's normal data locations. Each additional
**managed workspace** stores its own Codex home and desktop-app data under the
`fxcodex` support directory.

When `fxcodex` opens the desktop app, it launches or focuses the app instance
associated with the requested workspace. When it runs the Codex CLI, it points
`CODEX_HOME` at that workspace's home directory. No account is switched inside
Codex itself; each instance simply starts with a different profile.

The **current workspace** is the default when a command does not include a
workspace name. Selecting it does not close or modify instances that are
already running, and multiple desktop workspaces can remain open at once.

## Requirements

- macOS 14 or later
- The Codex desktop app for `fxcodex open`
- The `codex` executable in `PATH` for `fxcodex cli` and `fxcodex exec`
- Swift 6.3 or later only when building from source

## Installation

### Download a release

Download these files from the
[latest GitHub release](https://github.com/CaptureContext/fxcodex/releases/latest):

- `fxcodex-universal-apple-darwin`
- `fxcodex-universal-apple-darwin.sha256`

The universal executable runs natively on both Apple Silicon and Intel Macs.
Smaller architecture-specific `aarch64` and `x86_64` artifacts are available
from the same release.

Verify and install the universal executable:

```sh
cd ~/Downloads
shasum -a 256 --check fxcodex-universal-apple-darwin.sha256
install -d "$HOME/.local/bin"
install -m 755 fxcodex-universal-apple-darwin "$HOME/.local/bin/fxcodex"
"$HOME/.local/bin/fxcodex" version
```

If `fxcodex` is not found, add this line to `~/.zshrc` and start a new shell:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Release executables are signed with a Developer ID Application certificate,
use the hardened runtime and a secure timestamp, and are notarized by Apple.

### Build from source

Clone the repository with a Swift 6.3 toolchain available, then run:

```sh
make test
make install
```

`make install` builds a release executable and installs it to
`~/.local/bin/fxcodex`. Set `PREFIX` to choose a different installation prefix.

## Quick start

Your existing Codex setup is immediately available as `primary`. A typical
setup keeps the account already signed in to Codex there and creates a managed
workspace for another account:

```sh
fxcodex workspace create work --use --open
```

Sign in to the new window with the account for that workspace. Its session and
local state remain isolated from `primary`.

Workspace names must start and end with a lowercase letter or number and may
contain lowercase letters, numbers, and hyphens in between.

Open or focus a particular workspace later:

```sh
fxcodex open primary
fxcodex open work
```

Run `fxcodex open` without a name to choose interactively, or change the
default used by commands that omit a workspace name:

```sh
fxcodex use work
```

Inspect the current setup:

```sh
fxcodex workspace list
fxcodex status --all
```

## Desktop and terminal usage

Start an interactive Codex CLI session in a workspace:

```sh
fxcodex cli work
```

Run `codex exec` in a workspace:

```sh
fxcodex exec work -- "Review the changes in this repository"
```

When the workspace name is omitted, both commands use the current workspace:

```sh
fxcodex cli
fxcodex exec -- "Summarize this project"
```

Arguments after `--` are forwarded unchanged to `codex` or `codex exec`.

## Managing workspaces

| Task | Command |
| --- | --- |
| List workspaces | `fxcodex workspace list` |
| Create a workspace | `fxcodex workspace create <name>` |
| Create and select it | `fxcodex workspace create <name> --use` |
| Create and open it | `fxcodex workspace create <name> --open` |
| Open or focus a workspace | `fxcodex open [name]` |
| Select the current workspace | `fxcodex use [name]` |
| Rename the current managed workspace | `fxcodex workspace rename <new-name>` |
| Rename a specified managed workspace | `fxcodex workspace rename <old-name> <new-name>` |
| Clear managed workspace data | `fxcodex erase [name ...]` |
| Delete managed workspaces and their data | `fxcodex delete [name ...]` |

`erase` keeps a workspace definition but clears its Codex home, desktop-app
data, and integrations. `delete` removes the managed workspace completely.
Both commands require confirmation and only operate on managed workspaces.

Close a workspace's Codex app instance before renaming, erasing, or deleting
it. The `primary` workspace cannot be renamed, erased, or deleted.

## App naming

App renaming is optional and independent of workspace isolation. Rename a valid
`ChatGPT.app` immediately:

```sh
fxcodex rename
```

Restore the ChatGPT name:

```sh
fxcodex rename --undo
```

Enable automatic renaming before subsequent commands:

```sh
fxcodex preferences set auto-rename true
```

`fxcodex` only operates on `/Applications/ChatGPT.app` and
`/Applications/Codex.app` when the bundle identifier is `com.openai.codex`.
`ChatGPT Classic.app`, whose bundle identifier is `com.openai.chat`, is left
untouched. If both valid app names exist, `fxcodex` reports the ambiguity and
does not move either bundle.

Running `fxcodex rename --undo` also disables automatic renaming so a later
command does not immediately restore the Codex name. List the current settings
with `fxcodex preferences`.

## Updates

`fxcodex` updates itself from GitHub Releases. Patch updates are the default:

```sh
fxcodex update
fxcodex update --minor
fxcodex update --major
fxcodex update --latest
```

- `--patch` stays within the current major and minor version.
- `--minor` stays within the current major version.
- `--major` selects the newest stable release.
- `--latest` also considers prereleases.

The updater preserves the current executable kind: a universal installation
updates to the universal artifact, while an architecture-specific installation
updates to its matching architecture. Every downloaded executable is verified
against its published SHA-256 checksum before replacement.

Homebrew-managed installations are updated with `brew upgrade fxcodex`.
`fxcodex update` and automatic executable replacement intentionally defer to
Homebrew for those installations.

Automatic checks run at most once every 24 hours and do not prevent the
requested command from running if a check fails. Configure an update policy
anchored at a minimum version with:

```sh
fxcodex preferences set auto-update --patch-from 1.2.5
fxcodex preferences set auto-update --minor-from 1.5.0
fxcodex preferences set auto-update --major-from 2.0.0
fxcodex preferences set auto-update --latest-from 2.1.0
fxcodex preferences set auto-update --disabled
```

Patch policies stay within the anchor's major and minor line. Minor policies
stay within its major line. Major and latest policies have no upper bound.

Automatic updates apply only to an external `fxcodex` executable. Applications
that bundle `fxcodex`, such as the companion Raycast extension, manage their
bundled executable separately.

## Raycast integration

### Script Commands

`fxcodex` can install and maintain Raycast Script Commands for quickly opening
workspaces. Start the guided setup with:

```sh
fxcodex integrations raycast install
```

Or manage the Script Commands directly:

```sh
fxcodex integrations raycast install script-command
fxcodex integrations raycast status
fxcodex integrations raycast sync script-command
fxcodex integrations raycast uninstall script-command
```

By default, installation creates commands for every workspace and records the
integration so commands remain synchronized when workspaces are created,
renamed, erased, or deleted. Use `--current-only` during installation to create
only the current workspace's command, and `--directory <path>` to select the
Raycast Script Commands directory explicitly.

### Extension

A companion Raycast extension provides workspace navigation, management,
custom icons, executable selection, and preferences. It is prepared separately
for Raycast Store submission after the first CLI release; the Script Commands
above are available without it.

## Machine-readable output

Supported commands can return a versioned JSON envelope for scripts and other
integrations:

```sh
fxcodex --json status --all
FXCODEX_JSON=1 fxcodex workspace list
```

Use `--no-json` to override the environment variable. Interactive selection is
disabled when required input is missing in JSON mode, so automation should pass
workspace names and confirmation flags explicitly.

## Uninstalling

Run the guided uninstaller and choose whether to keep data, erase managed Codex
data while retaining workspace definitions, or remove the complete support
directory:

```sh
fxcodex uninstall
```

For non-interactive use, pass `--yes` together with one of `--leave-data`,
`--erase-data`, or `--delete-data`. Managed Raycast Script Commands are removed
in every mode. Erasing or deleting data is refused while a managed workspace is
running.

If the executable was installed somewhere `fxcodex` cannot remove itself from,
delete it manually after the command completes.

## Data and privacy

`fxcodex` stores its configuration and managed workspaces in:

```text
~/Library/Application Support/fxcodex/
├── configuration.json
├── instances.json
├── preferences.json
├── update-state.json
└── workspaces/
    └── <workspace-name>/
        ├── codex-home/
        └── user-data/
```

The `primary` workspace continues to use Codex's normal locations. Managed
workspace directories contain account-specific Codex state; treat them as
private data and do not commit or share them.

## Development

Common development commands are:

```sh
make build
make test
make release
make universal
```

The package targets macOS 14 and uses Swift 6 language mode. Run
`fxcodex help <command>` or `fxcodex <command> --help` for the complete CLI
reference.

## Publishing a release

Release versions use plain semantic versions such as `0.1.0` (without a `v`
prefix). Update the embedded version in
`Sources/fxcodex-cli/AppCommand.swift`, run `make test`, and push the
release-ready commit to `main`. Then run the `Release` workflow from GitHub
Actions and enter that version.

The workflow pins the release to the selected `main` commit, verifies that the
version matches the executable, resolves one dependency graph for both
architectures, builds and tests on Apple Silicon and Intel runners, and signs
and notarizes all final executables. After every check succeeds, it creates the
tag and publishes the release with post-signing SHA-256 checksum files:

- `fxcodex-aarch64-apple-darwin`
- `fxcodex-x86_64-apple-darwin`
- `fxcodex-universal-apple-darwin`

The release also includes the exact `Package.resolved` used by both builds.
The file stays ignored during normal development; download it alongside
GitHub's source archive when reproducing a release.

## License

`fxcodex` is available under the [MIT License](LICENSE).
