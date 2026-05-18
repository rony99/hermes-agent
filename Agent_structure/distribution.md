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

This keeps wheel installs functionally close to repo installs without requiring
users to keep a source checkout.

## Release Requirement

The one-liner depends on a public GitHub Release containing a `.whl` asset. If
the repository has no release or the selected release has no wheel, the
installer fails explicitly and tells the publisher to build with `uv build` and
upload `dist/*.whl`.
