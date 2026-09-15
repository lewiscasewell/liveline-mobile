#!/usr/bin/env bash
#
# Keeps the documentation honest. Run locally or in CI:
#
#   ./scripts/check-docs.sh
#
# Checks, in order:
#   1. every uploaded video URL is alone on its line (else GitHub renders a link)
#   2. documented dependency versions match the released version
#   3. every repo path mentioned in the docs actually exists
#   4. reports how many video placeholders are still outstanding (not a failure)
set -uo pipefail

cd "$(dirname "$0")/.."

DOCS=(README.md PARITY.md RELEASING.md packages/liveline-mobile/README.md)
fail=0
err() { echo "::error::$1"; echo "  ✗ $1"; fail=1; }

echo "==> 1. video embeds"
# GitHub swaps an attachment URL for a player only when the URL is the whole
# line. Inline (in a table cell, or after other text) it stays a plain link.
for f in "${DOCS[@]}"; do
  [[ -f "$f" ]] || continue
  while IFS=: read -r line _; do
    [[ -z "$line" ]] && continue
    err "$f:$line — video URL is not alone on its line, so it renders as a link, not a player"
  done < <(grep -n 'github\.com/user-attachments/assets/' "$f" \
           | grep -v '^\([0-9]*\):https://github\.com/user-attachments/assets/[A-Za-z0-9-]*$' \
           | cut -d: -f1 | sed 's/$/:/')
done

echo "==> 2. versions"
VERSION=$(node -p "require('./packages/liveline-mobile/package.json').version" 2>/dev/null)
if [[ -z "$VERSION" ]]; then
  err "could not read the package version"
else
  echo "  package version: $VERSION"
  while IFS=: read -r f line coord; do
    got=${coord##*:}; got=${got%\"*}
    [[ "$got" == "$VERSION" ]] \
      || err "$f:$line — Maven snippet pins $got, but the released version is $VERSION"
  done < <(grep -n -o 'io\.github\.lewiscasewell:liveline:[0-9][^")]*' "${DOCS[@]}" 2>/dev/null)

  while IFS=: read -r f line _; do
    err "$f:$line — SPM snippet points at a branch; pin a release instead (from: \"$VERSION\")"
  done < <(grep -n '\.package(url:.*branch:' "${DOCS[@]}" 2>/dev/null)
fi

echo "==> 3. referenced paths"
# Only backticked things that look like repo paths: a slash, no spaces, no
# ellipsis, and a known top-level directory.
for f in "${DOCS[@]}"; do
  [[ -f "$f" ]] || continue
  grep -o '`[^`]*`' "$f" | tr -d '`' | sed 's:/$::' \
    | grep -E '^(ios|android|packages|examples|scripts|\.github)/' \
    | grep -v '\.\.\.\|…\| \|\*' | sort -u \
    | while read -r p; do
        # RELEASING.md quotes the package's own `files` list, whose paths are
        # relative to the package root, so accept either location.
        [[ -e "$p" || -e "packages/liveline-mobile/$p" ]] \
          || err "$f — references \`$p\`, which does not exist"
      done
done

echo "==> 4. outstanding video placeholders"
for f in "${DOCS[@]}"; do
  [[ -f "$f" ]] || continue
  n=$(grep -ci '_video coming soon\._\|🎥 record:' "$f" 2>/dev/null | tr -d ' ')
  [[ "$n" -gt 0 ]] && echo "  $f: $n still to record"
done
todo=$(grep -c '☑ | ☐' PARITY.md 2>/dev/null | tr -d ' ')
[[ "$todo" -gt 0 ]] && echo "  PARITY.md: $todo features with no video captured"

echo
[[ $fail -eq 0 ]] && echo "docs OK" || echo "docs check failed"
exit $fail
