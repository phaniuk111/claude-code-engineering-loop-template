#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target="${1:-}"

usage() {
  echo "Usage: ./install.sh /path/to/target-repo" >&2
}

if [[ -z "$target" ]]; then
  usage
  exit 2
fi

mkdir -p "$target"
target="$(cd "$target" && pwd)"

if ! git -C "$target" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Target is not a Git repository: $target" >&2
  exit 2
fi

echo "Installing Claude engineering loop into $target"

mkdir -p "$target/.claude"
rsync -a \
  --exclude 'engineering-loop-baseline.sha' \
  --exclude 'engineering-loop-commands.jsonl' \
  --exclude 'engineering-loop-edits.jsonl' \
  --exclude 'engineering-loop-events.jsonl' \
  --exclude 'engineering-loop-mode' \
  --exclude 'engineering-loop-review-disposition.json' \
  --exclude 'engineering-loop-run-id' \
  --exclude 'engineering-loop-state.json' \
  --exclude 'settings.local.json' \
  "$source_root/.claude/" "$target/.claude/"

if [[ -f "$target/CLAUDE.md" ]]; then
  echo "Keeping existing CLAUDE.md"
  cp "$source_root/CLAUDE.md" "$target/CLAUDE.engineering-loop.example.md"
  echo "Wrote CLAUDE.engineering-loop.example.md for manual merge"
else
  cp "$source_root/CLAUDE.md" "$target/CLAUDE.md"
fi

if [[ ! -f "$target/.claude/settings.local.json" ]]; then
  cp "$source_root/.claude/settings.local.example.json" "$target/.claude/settings.local.json"
fi

gitignore="$target/.gitignore"
touch "$gitignore"

normalize_gitignore() {
  local tmp_file
  tmp_file="$(mktemp)"

  awk '
    $0 == ".claude/" {
      if (!replaced) {
        print "# Claude local files"
        print ".claude/settings.local.json"
        print ".claude/launch.json"
        print ".claude/engineering-loop-baseline.sha"
        print ".claude/engineering-loop-commands.jsonl"
        print ".claude/engineering-loop-edits.jsonl"
        print ".claude/engineering-loop-events.jsonl"
        print ".claude/engineering-loop-mode"
        print ".claude/engineering-loop-review-disposition.json"
        print ".claude/engineering-loop-run-id"
        print ".claude/engineering-loop-state.json"
        replaced = 1
      }
      next
    }
    { print }
  ' "$gitignore" > "$tmp_file"

  mv "$tmp_file" "$gitignore"
}

ensure_ignore() {
  local pattern="$1"
  if ! grep -Fxq "$pattern" "$gitignore"; then
    printf '%s\n' "$pattern" >> "$gitignore"
  fi
}

if grep -Fxq ".claude/" "$gitignore"; then
  echo "Replacing broad .claude/ ignore with precise local runtime ignores"
  normalize_gitignore
fi

ensure_ignore ".claude/settings.local.json"
ensure_ignore ".claude/engineering-loop-baseline.sha"
ensure_ignore ".claude/engineering-loop-commands.jsonl"
ensure_ignore ".claude/engineering-loop-edits.jsonl"
ensure_ignore ".claude/engineering-loop-events.jsonl"
ensure_ignore ".claude/engineering-loop-mode"
ensure_ignore ".claude/engineering-loop-review-disposition.json"
ensure_ignore ".claude/engineering-loop-run-id"
ensure_ignore ".claude/engineering-loop-state.json"

(
  cd "$target"
  printf 'placeholder\n' > .claude/engineering-loop-baseline.sha
  .claude/hooks/engineering-loop-stop.sh --fingerprint > .claude/engineering-loop-baseline.sha
  .claude/skills/engineering-loop/scripts/doctor.sh
)

echo
echo "Install complete. Restart Claude Code, then run /agents and /engineering-loop."
