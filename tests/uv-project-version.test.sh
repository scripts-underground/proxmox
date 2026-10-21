#!/usr/bin/env bash
# Real runtime-helper checks. Run as root only in a disposable guest.
set -euo pipefail
systemd-detect-virt -q || {
  printf 'Run this test inside a disposable VM/container.\n' >&2
  exit 1
}
test "$(id -u)" -eq 0

ROOT=$(realpath "$(dirname "${BASH_SOURCE[0]}")/..")
source "$ROOT/misc/core.func"
source "$ROOT/misc/error_handler.func"
source "$ROOT/misc/tools.func"
load_functions

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
exit_trap=$(trap -p EXIT)
export HOME="$work/home" INSTALL_LOG="$work/install.log"
unset XDG_DATA_HOME
mkdir "$HOME" "$work/project" "$work/uv-config" "$work/range"

cat > "$work/project/pyproject.toml" << 'EOF'
[project]
name = "python-selection-probe"
version = "0.0.0"
requires-python = ">=3.14"

[tool.uv]
required-version = "==0.12.13"
package = false
EOF
cat > "$work/uv-config/uv.toml" << 'EOF'
required-version = "==0.12.13"
EOF
cat > "$work/range/pyproject.toml" << 'EOF'
[tool.uv]
required-version = ">=0.12.13"
EOF

test "$(_uv_required_version "$work/project")" == 0.12.13
test "$(_uv_required_version "$work/uv-config")" == 0.12.13
if _uv_required_version "$work/range"; then
  printf 'A range must not be interpreted as an exact release tag.\n' >&2
  exit 1
fi
printf 'PASS pyproject.toml and uv.toml exact-pin parsing\n'

parse="$work/parse"
mkdir -p "$parse"/{precedence,masked,section,quoted,comment,bare}
printf 'required-version = "==0.12.22"\n' > "$parse/precedence/uv.toml"
printf '[tool.uv]\nrequired-version = "==0.12.13"\n' > "$parse/precedence/pyproject.toml"
printf 'python-preference = "managed"\n' > "$parse/masked/uv.toml"
printf '[tool.uv]\nrequired-version = "==0.12.13"\n' > "$parse/masked/pyproject.toml"
if _uv_required_version "$parse/masked"; then
  printf 'A uv.toml without a pin masks the pyproject pin, as uv does.\n' >&2
  exit 1
fi
printf '[project]\nrequired-version = "==9.9.9"\n\n[tool.uv] # uv\nrequired-version = "0.12.13"\n' > "$parse/section/pyproject.toml"
printf "[tool.uv]\nrequired-version = '==0.12.13' # pinned\n" > "$parse/quoted/pyproject.toml"
printf '[tool.uv]\n# required-version = "==0.1.0"\nrequired-version = "==0.12.13"\n' > "$parse/comment/pyproject.toml"
printf '[tool.uv]\nrequired-version = 0.12.13\n' > "$parse/bare/pyproject.toml"
test "$(_uv_required_version "$parse/precedence")" == 0.12.22
test "$(_uv_required_version "$parse/section")" == 0.12.13
test "$(_uv_required_version "$parse/quoted")" == 0.12.13
test "$(_uv_required_version "$parse/comment")" == 0.12.13
test "$(_uv_required_version "$parse/bare")" == 0.12.13
printf 'PASS uv.toml precedence, [tool.uv] only, quotes, comments, bare value\n'

UV_PROJECT_DIR="$work/project" setup_uv
test "$(/usr/local/bin/uv --version | cut -d' ' -f2)" == 0.12.13
test "$(get_cached_version uv)" == 0.12.13
test "$(trap -p EXIT)" == "$exit_trap"
printf 'PASS project pin installs the selected uv without replacing the caller trap\n'

if UV_PYTHON_DOWNLOADS=never /usr/local/bin/uv python find 3.14 > /dev/null 2>&1; then
  printf 'The test needs an isolated Python data directory.\n' >&2
  exit 1
fi
UV_PROJECT_DIR="$work/project" PYTHON_VERSION=3.14 setup_uv
python_path=$(UV_PYTHON_DOWNLOADS=never /usr/local/bin/uv python find 3.14)
"$python_path" -c 'import sys; assert sys.version_info[:2] == (3, 14); print("PASS same-version uv still installs the requested Python")'
test "$(/usr/local/bin/uv --version | cut -d' ' -f2)" == 0.12.13

UV_PROJECT_DIR="$work/project" PYTHON_VERSION=3.13 setup_uv
(cd "$work/project" && /usr/local/bin/uv sync --all-extras)
"$work/project/.venv/bin/python" -c 'import sys; assert sys.version_info[:2] == (3, 14); print("PASS uv sync selects the project-compatible Python despite a 3.13 setup request")'

UV_VERSION=0.12.22 UV_PROJECT_DIR="$work/project" setup_uv
test "$(/usr/local/bin/uv --version | cut -d' ' -f2)" == 0.12.22
test "$(get_cached_version uv)" == 0.12.22
printf 'PASS explicit UV_VERSION takes precedence over the project pin\n'

UV_PROJECT_DIR="$work/project" setup_uv
test "$(/usr/local/bin/uv --version | cut -d' ' -f2)" == 0.12.13
printf 'PASS project pin can select an older uv release\n'

latest=$(get_latest_github_release astral-sh/uv)
UV_PROJECT_DIR="$work/range" setup_uv
test "$(/usr/local/bin/uv --version | cut -d' ' -f2)" == "$latest"
test "$(get_cached_version uv)" == "$latest"
test "$(trap -p EXIT)" == "$exit_trap"
printf 'PASS compatible open range selects the latest stable release\n'

mkdir "$work/closed-range"
cat > "$work/closed-range/pyproject.toml" << 'EOF'
[project]
name = "closed-range-probe"
version = "0.0.0"
requires-python = ">=3.14"
[tool.uv]
required-version = ">=0.12.13,<0.12.23"
package = false
EOF
UV_PROJECT_DIR="$work/closed-range" setup_uv
test "$(/usr/local/bin/uv --version | cut -d' ' -f2)" == 0.12.22
(cd "$work/closed-range" && /usr/local/bin/uv sync)
"$work/closed-range/.venv/bin/python" -c 'import sys; assert sys.version_info[:2] == (3, 14); print("PASS real project consumer accepts selected closed-range uv and Python")'
