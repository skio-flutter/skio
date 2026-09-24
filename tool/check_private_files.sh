#!/usr/bin/env bash
# Blocks private files and secrets from entering the repository.
#
#   tool/check_private_files.sh --staged   # files staged for commit (pre-commit hook)
#   tool/check_private_files.sh --all      # every tracked file (CI)
#
# .gitignore already hides these files, but `git add -f` or a new file type
# can bypass it; this is the second line of defence.
set -euo pipefail

mode="${1:---staged}"
case "$mode" in
  --staged) files=$(git diff --cached --name-only --diff-filter=ACMR) ;;
  --all) files=$(git ls-files) ;;
  *) echo "usage: $0 [--staged|--all]" >&2; exit 2 ;;
esac

# Paths that must never be committed (extended regex, matched against the path).
blocked_paths='(^|/)private/|(^|/)\.env($|\.)|\.(pem|p12|p8|key|jks|keystore|mobileprovision|hprof)$|(^|/)key\.properties$|(^|/)local\.properties$|(^|/)google-services\.json$|(^|/)GoogleService-Info\.plist$|(^|/)(pub-)?credentials\.json$|(^|/)service-account[^/]*\.json$|\.private\.|(^|/)settings\.local\.json$'

# Content that looks like a secret.
blocked_content='-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|gh[pousr]_[0-9A-Za-z]{36}|github_pat_[0-9A-Za-z_]{40,}|xox[baprs]-[0-9A-Za-z-]{10,}|"refreshToken"[[:space:]]*:|sk-ant-[0-9A-Za-z_-]{20,}|sk-[0-9A-Za-z]{40,}'

# Allow a line to opt out with this marker (e.g. test fixtures).
allow_marker='check-private-files: allow'

# Optional local-only list of words that must never be committed (one per
# line). It lives in the git-ignored private/ folder, so the words themselves
# never reach GitHub.
words_file="$(git rev-parse --show-toplevel)/private/blocked_words.txt"

failed=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [[ "$f" =~ $blocked_paths ]]; then
    echo "BLOCKED path: $f" >&2
    failed=1
    continue
  fi
  [ -f "$f" ] || continue
  # Skip binary files and this script (it contains the patterns).
  [ "$f" = "tool/check_private_files.sh" ] && continue
  grep -Iq . "$f" 2>/dev/null || continue
  if [ "$mode" = "--staged" ]; then
    content=$(git show ":$f")
  else
    content=$(cat "$f")
  fi
  hits=$(printf '%s\n' "$content" | grep -nE -- "$blocked_content" | grep -v "$allow_marker" || true)
  if [ -s "$words_file" ]; then
    word_hits=$(printf '%s\n' "$content" | grep -niwF -f "$words_file" || true)
    if [ -n "$word_hits" ]; then
      echo "BLOCKED private word in $f (see private/blocked_words.txt)" >&2
      failed=1
    fi
  fi
  if [ -n "$hits" ]; then
    echo "BLOCKED secret-like content in $f:" >&2
    printf '%s\n' "$hits" | sed -E 's/(.{0,60}).*/    \1.../' >&2
    failed=1
  fi
done <<< "$files"

if [ "$failed" -ne 0 ]; then
  cat >&2 <<'EOF'

Private files or secrets were found. Remove them from the commit
(git rm --cached <file>) and keep them in private/ or outside the repo.
EOF
  exit 1
fi
echo "check_private_files: OK ($mode)"
