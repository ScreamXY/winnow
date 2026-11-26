#!/bin/zsh
# Regenerates the Xcode project with the pinned XcodeGen version.
#
#   <this script>            regenerate from the spec (commit the result)
#   <this script> --check    regenerate and fail if any generated file changed (CI drift check)
#
# Extra arguments go to `xcodegen generate`. The generated project, Info.plists, entitlements
# and shared schemes are committed; the spec stays the source of truth. A matching local
# `xcodegen` is used when present, otherwise the release build is downloaded once and cached.
# Xcode rewrites shared scheme files in its own format whenever it has the project open, so
# the check ignores scheme-file changes; every spec change also changes project.pbxproj.
set -euo pipefail

XCODEGEN_VERSION="2.46.0"
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
SPEC="project.yml"

cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

check=0
args=()
for arg in "$@"; do
  case "$arg" in
    --check) check=1 ;;
    *) args+=("$arg") ;;
  esac
done

resolve_xcodegen() {
  if command -v xcodegen >/dev/null 2>&1 \
     && [[ "$(xcodegen --version 2>/dev/null)" == "Version: $XCODEGEN_VERSION" ]]; then
    command -v xcodegen
    return
  fi
  local cache="${XCODEGEN_CACHE_DIR:-$HOME/Library/Caches/screamxy-xcodegen}/$XCODEGEN_VERSION"
  local bin="$cache/xcodegen/bin/xcodegen"
  if [[ ! -x "$bin" ]]; then
    local tmp
    tmp="$(mktemp -d)"
    echo "Downloading XcodeGen $XCODEGEN_VERSION" >&2
    curl -sSfL -o "$tmp/xcodegen.zip" \
      "https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip"
    echo "$XCODEGEN_SHA256  $tmp/xcodegen.zip" | shasum -a 256 -c - >/dev/null
    mkdir -p "$cache"
    unzip -q -o "$tmp/xcodegen.zip" -d "$cache"
    rm -rf "$tmp"
  fi
  echo "$bin"
}

xcodegen_bin="$(resolve_xcodegen)"
generated_state() { git status --porcelain --untracked-files=all | grep -v "xcshareddata/xcschemes/" | sort || true; }
before="$(generated_state)"
"$xcodegen_bin" generate --spec "$SPEC" "${args[@]}"

if (( check )); then
  after="$(generated_state)"
  changed="$(comm -13 <(print -r -- "$before") <(print -r -- "$after"))"
  if [[ -n "$changed" ]]; then
    echo "Generated project is out of date with $SPEC. Run $0 and commit the result:" >&2
    print -r -- "$changed" >&2
    git --no-pager diff --stat >&2
    exit 1
  fi
  echo "Generated project matches $SPEC (XcodeGen $XCODEGEN_VERSION)."
fi
