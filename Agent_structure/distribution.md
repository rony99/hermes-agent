# Distribution And Installation

## Rony Release Wheel Installer

- User-facing one-liner:
  `curl -fsSL https://raw.githubusercontent.com/rony99/hermes-agent/main/scripts/install-rony.sh | bash`
- Installer file: `scripts/install-rony.sh`.
- Code install source: GitHub Release wheel asset from `rony99/hermes-agent`.
- The installer intentionally does not clone or pip-install the source checkout.
- Default install directory: `$HERMES_HOME/hermes-agent-rony`.
- Default data directory: `$HOME/.hermes`, overridable with `HERMES_HOME` or `--hermes-home`.
- Default Python runtime: Python 3.11 installed/found by `uv`.
- Default extras: `all`, overridable with `HERMES_EXTRAS` or `--extras`.

## Bundled Resource Rule

Hermes wheels do not include top-level non-package directories such as
`skills/` and `optional-skills/`. The installer therefore installs code from the
wheel, then downloads the matching GitHub release source archive only to copy
bundled runtime resources into:

```text
$HERMES_HOME/hermes-agent-rony/bundled/
|-- skills/
|-- optional-skills/
`-- plugins/
```

The generated `hermes` launcher exports:

- `HERMES_BUNDLED_SKILLS`
- `HERMES_OPTIONAL_SKILLS`
- `HERMES_BUNDLED_PLUGINS`

Before writing the launcher, the installer removes any existing
`$HOME/.local/bin/hermes` file or symlink. This avoids following an old symlink
into a source-checkout venv and overwriting that venv's generated entry point.

This keeps wheel installs functionally close to repo installs without requiring
users to keep a source checkout.

## Release Requirement

The one-liner depends on a public GitHub Release containing a `.whl` asset. If
the repository has no release or the selected release has no wheel, the
installer fails explicitly and tells the publisher to build with `uv build` and
upload `dist/*.whl`.

Shixian-marked releases should stay based on the current `rony99/hermes-agent`
release branch state, then add the Shixian-specific session/thinking patches on
top. The CLI display version uses a `_shixian` suffix (for example
`0.13.0_shixian`), while the wheel metadata must use the PEP 440 local-version
form (for example `0.13.0+shixian`).

## Canonical Shixian Release Branch

`release/shixian` is the canonical source branch for Shixian releases.
Completed Shixian behavior must land on this branch before packaging. Release
wheels and GitHub Releases should be built from this branch only.

Small, non-experimental changes may be developed and tested directly on
`release/shixian`. Use a separate feature branch for large changes, risky
experiments, or when the user explicitly asks for isolated development.

The current required Shixian release behaviors are:

- Send the Hermes session id in outbound HTTP headers as
  `X-Hermes-Code-Session-Id`.
- Preserve assistant thinking/reasoning history, including signed and redacted
  Anthropic thinking blocks.
- Omit the session header for background review or other non-user-main-flow
  spontaneous agent requests.
