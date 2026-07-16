# Extension API

Raycast extensions and other local frontends should invoke an absolute path to
`fxcodex`, request JSON, decode the response, and let the process exit. No daemon
or persistent connection is required.

Pass `--json` before the subcommand or directly to a supported command:

```sh
fxcodex --json status
fxcodex workspace list --json
fxcodex open work --json
fxcodex delete work personal --yes --json
```

Set `FXCODEX_JSON=1` to make JSON the default. An explicit `--no-json`
overrides the environment for a single invocation.

Frontends that ship a fixed, compatibility-tested binary should also set
`FXCODEX_DISABLE_AUTO_UPDATE=1`. This keeps automatic application renaming
enabled while preventing the bundled executable from replacing itself. An
external user-managed binary can omit the variable and follow the configured
automatic-update preference normally.

Successful responses are written to standard output:

```json
{
  "api_version": 1,
  "ok": true,
  "data": {}
}
```

Errors are written to standard error and use a nonzero process exit code:

```json
{
  "api_version": 1,
  "ok": false,
  "error": {
    "code": "workspace_not_found",
    "message": "Workspace 'work' does not exist."
  }
}
```

Non-fatal automatic-preference warnings are written to standard error as
individual JSON objects while the successful command response remains on
standard output:

```json
{
  "api_version": 1,
  "warning": {
    "code": "application_name_conflict",
    "message": "Both ChatGPT.app and Codex.app are present; Codex.app will be used."
  }
}
```

All JSON object property names use lower snake case, including properties in
nested response data. Enum and outcome strings retain their documented values.

The machine interface is available for:

- `version`
- `status`
- `preferences list`
- `preferences set`
- `rename`
- `update`
- `workspace list`
- `workspace create`
- `workspace rename`
- `workspace use` and its root `use` alias
- `workspace open` and its root `open` alias
- `workspace delete` and its root `delete` alias
- `workspace erase` and its root `erase` alias
- `integrations raycast status`

JSON mode never presents an interactive prompt. `use` requires a workspace
name. `delete` and `erase` require at least one workspace name and `--yes`.
`open` without a name opens or focuses the current workspace.

`rename` requests the `Codex.app` name and returns a
`CodexApplicationRenameResult`. `rename --undo` requests `ChatGPT.app`. The
result outcome is `renamed`, `already-named`, or `conflict`; a conflict is
non-fatal and leaves both application bundles in place. The command validates
the `com.openai.codex` bundle identifier and never treats `ChatGPT Classic.app`
as the Codex application.

`update` defaults to the patch channel and accepts `--patch`, `--minor`,
`--major`, or `--latest`. It returns an `UpdateResult` whose outcome is `updated` or
`already-current`. A frontend that owns a private fxcodex binary can use this
command to update it in place, then restart subsequent invocations from the
same absolute path.

The persisted JSON property `auto_update` uses a constraint anchored at a
minimum version. Its representation contains `channel` and `from`, for example
`{"channel":"minor","from":"1.2.3"}`. Configure the `auto-update` CLI
preference with `--patch-from`, `--minor-from`, `--major-from`, or
`--latest-from`; use `--disabled` to turn it off. `from` is a lower bound, not
a maximum version.

`status` returns basic paths and the current workspace by default. A frontend
can request additional data with `--list-preferences`, `--list-workspaces`,
`--list-integrations`, or `--all`. The equivalent environment variables are:

- `FXCODEX_STATUS_LIST_PREFERENCES`
- `FXCODEX_STATUS_LIST_WORKSPACES`
- `FXCODEX_STATUS_LIST_INTEGRATIONS`
- `FXCODEX_STATUS_ALL`

Set a scoped environment variable to `-1` to exclude that section even when
all sections are enabled. On the command line, use the corresponding
`--no-list-...` flag.

`cli`, `exec`, `uninstall`, and integration installation commands are
intentionally outside the machine API. A frontend should use workspace/status
commands and refresh its state after mutations. Raycast Script Commands remain
an optional integration.
