#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-upstream}"
STATE_FILE=".upstream-release-state.json"

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") <hooke_archive_or_exe> <shinchiro_archive>

Example:
  $(basename "$0") /path/mpv-lazy-20260210.exe /path/mpv-x86_64-20260307-git-f9190e5.7z

Notes:
- Run this script from any path; it will operate on repo: $ROOT_DIR
- Working tree must be clean.
- It updates branch: $UPSTREAM_BRANCH
- Rebuilds from hooke007 package, then replaces only mpv.exe/mpv.com from shinchiro.
- Optional envs HOOKE_LABEL / SHINCHIRO_LABEL customize the commit message.
- Optional envs HOOKE_TAG / SHINCHIRO_TAG are recorded in the branch state file.
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
}

find_extractor() {
  if command -v 7z >/dev/null 2>&1; then
    printf '%s\n' "7z"
    return
  fi
  if command -v 7zz >/dev/null 2>&1; then
    printf '%s\n' "7zz"
    return
  fi
  if [[ -x "$ROOT_DIR/7z.exe" ]]; then
    printf '%s\n' "$ROOT_DIR/7z.exe"
    return
  fi
  echo "Need 7z, 7zz, or bundled 7z.exe for extraction." >&2
  exit 1
}

to_extractor_path() {
  local path="$1"
  if [[ "${EXTRACTOR[0]}" == *.exe ]]; then
    wslpath -w "$path"
  else
    printf '%s\n' "$path"
  fi
}

extract_archive() {
  local archive_path="$1"
  local output_dir="$2"
  local archive_arg output_arg
  archive_arg="$(to_extractor_path "$archive_path")"
  output_arg="$(to_extractor_path "$output_dir")"
  "${EXTRACTOR[@]}" x -y "-o${output_arg}" "$archive_arg" >/dev/null
}

resolve_overlay_root() {
  local dir="$1"
  local child_count
  child_count="$(find "$dir" -mindepth 1 -maxdepth 1 | wc -l)"
  if [[ "$child_count" -eq 1 ]]; then
    local first_entry
    first_entry="$(find "$dir" -mindepth 1 -maxdepth 1 | head -n 1)"
    if [[ -d "$first_entry" ]]; then
      printf '%s\n' "$first_entry"
      return
    fi
  fi
  printf '%s\n' "$dir"
}

copy_shinchiro_binaries() {
  local source_root="$1"
  local target_root="$2"
  local file
  for file in mpv.exe mpv.com; do
    if [[ -f "$source_root/$file" ]]; then
      cp -f "$source_root/$file" "$target_root/$file"
    elif [[ -f "$source_root/mpv/$file" ]]; then
      cp -f "$source_root/mpv/$file" "$target_root/$file"
    else
      echo "Missing $file in shinchiro archive." >&2
      exit 1
    fi
  done
}

checkout_target_branch() {
  local branch="$1"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch" >/dev/null
    return
  fi
  if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git checkout -b "$branch" "origin/$branch" >/dev/null
    return
  fi
  git checkout -b "$branch" >/dev/null
}

select_commit_label() {
  local hooke_label="$1"
  local shinchiro_label="$2"
  local changed_files non_binary_changes
  changed_files="$(git diff --cached --name-only)"
  non_binary_changes="$(printf '%s\n' "$changed_files" | grep -Ev '^(\.upstream-release-state\.json|mpv\.exe|mpv\.com)$' || true)"
  if [[ -n "$non_binary_changes" ]]; then
    printf '%s\n' "$hooke_label"
  else
    printf '%s\n' "$shinchiro_label"
  fi
}

write_release_state() {
  local state_path="$ROOT_DIR/$STATE_FILE"
  cat >"$state_path" <<EOF
{
  "hooke_tag": "${HOOKE_TAG:-}",
  "hooke_label": "${HOOKE_LABEL:-}",
  "hooke_asset": "$(basename "$HOOKE_SRC")",
  "shinchiro_tag": "${SHINCHIRO_TAG:-}",
  "shinchiro_label": "${SHINCHIRO_LABEL:-}",
  "shinchiro_asset": "$(basename "$SHINCHIRO_SRC")"
}
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

HOOKE_SRC="$1"
SHINCHIRO_SRC="$2"

if [[ ! -f "$HOOKE_SRC" ]]; then
  echo "hooke archive not found: $HOOKE_SRC" >&2
  exit 1
fi
if [[ ! -f "$SHINCHIRO_SRC" ]]; then
  echo "shinchiro archive not found: $SHINCHIRO_SRC" >&2
  exit 1
fi

require_cmd git
require_cmd rsync
EXTRACTOR=("$(find_extractor)")
if [[ "${EXTRACTOR[0]}" == *.exe ]]; then
  require_cmd wslpath
fi

cd "$ROOT_DIR"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Working tree is not clean. Please commit/stash first." >&2
  exit 1
fi

CURRENT_BRANCH="$(git symbolic-ref --short HEAD)"
trap 'git checkout "$CURRENT_BRANCH" >/dev/null 2>&1 || true; rm -rf "$TMP_DIR"' EXIT

TMP_PARENT="$ROOT_DIR/.tmp"
if [[ "${EXTRACTOR[0]}" == *.exe ]]; then
  mkdir -p "$TMP_PARENT"
  TMP_DIR="$(mktemp -d "$TMP_PARENT/rebuild.XXXXXX")"
else
  TMP_DIR="$(mktemp -d)"
fi
HOOKE_DIR="$TMP_DIR/hooke"
SHINCHIRO_DIR="$TMP_DIR/shinchiro"
STAGE_DIR="$TMP_DIR/stage"
mkdir -p "$HOOKE_DIR" "$SHINCHIRO_DIR" "$STAGE_DIR"

echo "[1/5] Extracting hooke package..."
extract_archive "$HOOKE_SRC" "$HOOKE_DIR"

echo "[2/5] Extracting shinchiro package..."
extract_archive "$SHINCHIRO_SRC" "$SHINCHIRO_DIR"

echo "[3/5] Building stage (hooke base + shinchiro mpv binaries)..."
HOOKE_ROOT="$(resolve_overlay_root "$HOOKE_DIR")"
SHINCHIRO_ROOT="$(resolve_overlay_root "$SHINCHIRO_DIR")"
cp -a "$HOOKE_ROOT/." "$STAGE_DIR/"
copy_shinchiro_binaries "$SHINCHIRO_ROOT" "$STAGE_DIR"

echo "[4/5] Updating branch '$UPSTREAM_BRANCH'..."
checkout_target_branch "$UPSTREAM_BRANCH"

rsync -a --delete \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='.gitattributes' \
  --exclude='.gitignore' \
  --exclude='tools/' \
  --exclude='docs/' \
  "$STAGE_DIR/" "$ROOT_DIR/"

if ! git diff --quiet || ! git diff --cached --quiet; then
  write_release_state
  git add -A
  if git diff --cached --quiet; then
    echo "No staged changes after normalization on $UPSTREAM_BRANCH"
  else
    HOOKE_NAME="${HOOKE_LABEL:-$(basename "$HOOKE_SRC")}"
    SHINCHIRO_NAME="${SHINCHIRO_LABEL:-$(basename "$SHINCHIRO_SRC")}"
    COMMIT_LABEL="$(select_commit_label "$HOOKE_NAME" "$SHINCHIRO_NAME")"
    git commit -m "upstream ${COMMIT_LABEL}"
    echo "Committed on $UPSTREAM_BRANCH"
  fi
else
  echo "No changes detected on $UPSTREAM_BRANCH"
fi

echo "[5/5] Done."
