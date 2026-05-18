#!/usr/bin/env bash
# Installer for rony99/hermes-agent release wheels.
#
# Intended usage:
#   curl -fsSL https://raw.githubusercontent.com/rony99/hermes-agent/main/scripts/install-rony.sh | bash
#
# This installer deliberately installs code from a GitHub Release wheel. It does
# not clone or pip-install the source repository. Bundled runtime resources are
# copied from the matching release source archive because wheels do not include
# Hermes' top-level skills/ and optional-skills/ directories.

set -euo pipefail

REPO="${HERMES_GITHUB_REPO:-rony99/hermes-agent}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
INSTALL_DIR="${HERMES_INSTALL_DIR:-$HERMES_HOME/hermes-agent-rony}"
PYTHON_VERSION="${HERMES_PYTHON_VERSION:-3.11}"
EXTRAS="${HERMES_EXTRAS:-all}"
VERSION="${HERMES_VERSION:-}"
WHEEL_URL="${HERMES_WHEEL_URL:-}"
RUN_SETUP=true
DRY_RUN=false

if [ -n "${PYTHONPATH:-}" ]; then
    unset PYTHONPATH
fi
if [ -n "${PYTHONHOME:-}" ]; then
    unset PYTHONHOME
fi

usage() {
    cat <<EOF
Hermes Agent installer for rony99/hermes-agent release wheels.

Usage:
  install-rony.sh [OPTIONS]

Options:
  --version TAG       Install a specific GitHub release tag instead of latest.
  --wheel-url URL     Install this wheel URL directly.
  --extras LIST       Python extras to install. Default: all. Use "" for none.
  --dir PATH          Install venv under PATH. Default: \$HERMES_HOME/hermes-agent-rony.
  --hermes-home PATH  Hermes data/config directory. Default: ~/.hermes.
  --skip-setup        Do not run the interactive setup wizard after install.
  --dry-run           Print the install plan and exit without changes.
  -h, --help          Show this help.

Environment:
  HERMES_GITHUB_REPO      Default: rony99/hermes-agent
  HERMES_VERSION          Same as --version
  HERMES_WHEEL_URL        Same as --wheel-url
  HERMES_EXTRAS           Same as --extras
  HERMES_INSTALL_DIR      Same as --dir
  HERMES_HOME             Same as --hermes-home
  HERMES_PYTHON_VERSION   Default: 3.11
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version)
            VERSION="${2:?--version requires a tag}"
            shift 2
            ;;
        --wheel-url)
            WHEEL_URL="${2:?--wheel-url requires a URL}"
            shift 2
            ;;
        --extras)
            EXTRAS="${2-}"
            shift 2
            ;;
        --dir)
            INSTALL_DIR="${2:?--dir requires a path}"
            shift 2
            ;;
        --hermes-home)
            HERMES_HOME="${2:?--hermes-home requires a path}"
            shift 2
            ;;
        --skip-setup)
            RUN_SETUP=false
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

log() {
    printf '%s\n' "-> $*" >&2
}

ok() {
    printf 'OK %s\n' "$*" >&2
}

warn() {
    printf 'WARN %s\n' "$*" >&2
}

fail() {
    printf 'ERROR %s\n' "$*" >&2
    exit 1
}

is_termux() {
    [ -n "${TERMUX_VERSION:-}" ] || [[ "${PREFIX:-}" == *"com.termux/files/usr"* ]]
}

command_link_dir() {
    if is_termux && [ -n "${PREFIX:-}" ]; then
        printf '%s\n' "$PREFIX/bin"
    else
        printf '%s\n' "$HOME/.local/bin"
    fi
}

find_uv() {
    if command -v uv >/dev/null 2>&1; then
        command -v uv
    elif [ -x "$HOME/.local/bin/uv" ]; then
        printf '%s\n' "$HOME/.local/bin/uv"
    elif [ -x "$HOME/.cargo/bin/uv" ]; then
        printf '%s\n' "$HOME/.cargo/bin/uv"
    else
        return 1
    fi
}

ensure_uv() {
    local uv_cmd
    if uv_cmd="$(find_uv)"; then
        printf '%s\n' "$uv_cmd"
        return 0
    fi

    log "uv not found; installing uv"
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
        fail "failed to install uv. Install it manually from https://docs.astral.sh/uv/ and rerun."
    fi

    if uv_cmd="$(find_uv)"; then
        printf '%s\n' "$uv_cmd"
        return 0
    fi
    fail "uv installed but is not on PATH"
}

ensure_python() {
    local uv_cmd="$1"
    if "$uv_cmd" python find "$PYTHON_VERSION" >/dev/null 2>&1; then
        "$uv_cmd" python find "$PYTHON_VERSION"
        return 0
    fi

    log "Python $PYTHON_VERSION not found; installing via uv"
    "$uv_cmd" python install "$PYTHON_VERSION"
    "$uv_cmd" python find "$PYTHON_VERSION"
}

resolve_release_info() {
    local python_bin="$1"
    local release_api
    if [ -n "$VERSION" ]; then
        release_api="https://api.github.com/repos/$REPO/releases/tags/$VERSION"
    else
        release_api="https://api.github.com/repos/$REPO/releases/latest"
    fi

"$python_bin" - "$release_api" "$REPO" <<'PY'
import json
import sys
import urllib.error
import urllib.request

api_url = sys.argv[1]
repo = sys.argv[2]
request = urllib.request.Request(
    api_url,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "hermes-rony-installer",
    },
)
try:
    with urllib.request.urlopen(request, timeout=25) as response:
        payload = json.loads(response.read().decode("utf-8"))
except urllib.error.HTTPError as exc:
    print(
        f"failed to read GitHub release metadata for {repo}: HTTP {exc.code}",
        file=sys.stderr,
    )
    sys.exit(1)
except Exception as exc:
    print(f"failed to read GitHub release metadata for {repo}: {exc}", file=sys.stderr)
    sys.exit(1)

assets = payload.get("assets") or []
wheels = [
    asset
    for asset in assets
    if str(asset.get("name", "")).endswith(".whl")
    and asset.get("browser_download_url")
]
if not wheels:
    tag = payload.get("tag_name") or "requested release"
    print(
        f"release {tag!r} for {repo} has no .whl asset. "
        "Build with `uv build` and upload dist/*.whl to the GitHub release.",
        file=sys.stderr,
    )
    sys.exit(1)

wheels.sort(
    key=lambda asset: (
        not str(asset.get("name", "")).startswith("hermes_agent-"),
        str(asset.get("name", "")),
    )
)
tag = payload.get("tag_name") or ""
if not tag:
    print(f"release metadata for {repo} did not include tag_name", file=sys.stderr)
    sys.exit(1)
print(f"{tag}\t{wheels[0]['browser_download_url']}")
PY
}

package_spec_for_wheel() {
    local wheel="$1"
    if [ -n "$EXTRAS" ]; then
        printf 'hermes-agent[%s] @ %s\n' "$EXTRAS" "$wheel"
    else
        printf 'hermes-agent @ %s\n' "$wheel"
    fi
}

install_launcher() {
    local link_dir="$1"
    mkdir -p "$link_dir"
    cat > "$link_dir/hermes" <<EOF
#!/usr/bin/env sh
: "\${HERMES_HOME:=$HERMES_HOME}"
export HERMES_HOME
export HERMES_BUNDLED_SKILLS="$INSTALL_DIR/bundled/skills"
export HERMES_OPTIONAL_SKILLS="$INSTALL_DIR/bundled/optional-skills"
export HERMES_BUNDLED_PLUGINS="$INSTALL_DIR/bundled/plugins"
exec "$INSTALL_DIR/venv/bin/hermes" "\$@"
EOF
    chmod +x "$link_dir/hermes"
    ok "installed launcher: $link_dir/hermes"
    case ":$PATH:" in
        *":$link_dir:"*) ;;
        *)
            warn "$link_dir is not on PATH. Add it to your shell profile or run: $link_dir/hermes"
            ;;
    esac
}

download_bundled_resources() {
    local python_bin="$1"
    local release_tag="$2"

    if [ -z "$release_tag" ]; then
        warn "No release tag available; bundled skills/plugins will not be installed. Pass --version with --wheel-url to enable resource install."
        return 0
    fi

    local tmp_dir archive source_root resource_url
    tmp_dir="$(mktemp -d)"
    archive="$tmp_dir/source.tar.gz"
    resource_url="https://github.com/$REPO/archive/refs/tags/$release_tag.tar.gz"

    log "Downloading bundled resources for $release_tag"
    "$python_bin" - "$resource_url" "$archive" <<'PY'
import sys
import urllib.error
import urllib.request

url, output = sys.argv[1], sys.argv[2]
request = urllib.request.Request(url, headers={"User-Agent": "hermes-rony-installer"})
try:
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
except urllib.error.HTTPError as exc:
    print(f"failed to download bundled resources: HTTP {exc.code}", file=sys.stderr)
    sys.exit(1)
except Exception as exc:
    print(f"failed to download bundled resources: {exc}", file=sys.stderr)
    sys.exit(1)
with open(output, "wb") as f:
    f.write(data)
PY

    tar -xzf "$archive" -C "$tmp_dir"
    source_root="$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ -z "$source_root" ] || [ ! -d "$source_root" ]; then
        rm -rf "$tmp_dir"
        fail "release archive did not contain a source directory"
    fi

    rm -rf "$INSTALL_DIR/bundled"
    mkdir -p "$INSTALL_DIR/bundled"
    for name in skills optional-skills plugins; do
        if [ -d "$source_root/$name" ]; then
            cp -R "$source_root/$name" "$INSTALL_DIR/bundled/$name"
        else
            warn "release archive has no $name directory"
        fi
    done
    rm -rf "$tmp_dir"
    ok "installed bundled resources"
}

create_user_files() {
    mkdir -p "$HERMES_HOME" "$HERMES_HOME/logs" "$HERMES_HOME/sessions" "$HERMES_HOME/skills"
    if [ ! -f "$HERMES_HOME/.env" ]; then
        : > "$HERMES_HOME/.env"
        ok "created $HERMES_HOME/.env"
    fi
    if [ ! -f "$HERMES_HOME/config.yaml" ]; then
        cat > "$HERMES_HOME/config.yaml" <<'EOF'
model:
  provider: ''
  default: ''
agent:
  reasoning_effort: medium
display:
  show_reasoning: false
EOF
        ok "created $HERMES_HOME/config.yaml"
    fi
}

main() {
    log "Hermes release-wheel install"
    log "Repository: $REPO"
    log "Hermes home: $HERMES_HOME"
    log "Install dir: $INSTALL_DIR"

    local uv_cmd python_bin release_info release_tag wheel package_spec link_dir
    uv_cmd="$(ensure_uv)"
    python_bin="$(ensure_python "$uv_cmd")"
    if [ -n "$WHEEL_URL" ]; then
        release_tag="$VERSION"
        wheel="$WHEEL_URL"
    else
        release_info="$(resolve_release_info "$python_bin")"
        IFS="$(printf '\t')" read -r release_tag wheel <<EOF
$release_info
EOF
    fi
    package_spec="$(package_spec_for_wheel "$wheel")"
    link_dir="$(command_link_dir)"

    if [ -n "$release_tag" ]; then
        log "Release: $release_tag"
    fi
    log "Wheel: $wheel"
    log "Package spec: $package_spec"

    if [ "$DRY_RUN" = true ]; then
        log "Dry run; no changes made"
        return 0
    fi

    if [ -d "$INSTALL_DIR/.git" ]; then
        fail "$INSTALL_DIR is a git checkout. Use --dir for a wheel install, or remove the source checkout first."
    fi

    mkdir -p "$INSTALL_DIR"
    log "Creating virtual environment"
    rm -rf "$INSTALL_DIR/venv"
    "$uv_cmd" venv "$INSTALL_DIR/venv" --python "$PYTHON_VERSION"

    log "Installing Hermes from release wheel"
    "$uv_cmd" pip install --python "$INSTALL_DIR/venv/bin/python" "$package_spec"
    download_bundled_resources "$INSTALL_DIR/venv/bin/python" "$release_tag"

    create_user_files
    install_launcher "$link_dir"

    if "$INSTALL_DIR/venv/bin/hermes" --version >/dev/null; then
        ok "hermes command is runnable"
    else
        fail "hermes installed but failed to run"
    fi

    if [ "$RUN_SETUP" = true ]; then
        if [ -t 0 ] || [ -r /dev/tty ]; then
            log "Starting setup wizard"
            "$INSTALL_DIR/venv/bin/hermes" setup < /dev/tty
        else
            warn "No interactive TTY; skipping setup wizard. Run: hermes setup"
        fi
    else
        log "Setup wizard skipped. Run later: hermes setup"
    fi

    ok "install complete"
    printf '\nRun Hermes with:\n  hermes\n'
}

main "$@"
