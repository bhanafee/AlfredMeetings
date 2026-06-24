#!/bin/bash
# Drift guard for THIRD-PARTY-NOTICES.md.
#
# Rebuilding the full venv in CI is impractical (multi-GB PyTorch, Apple-Silicon-only
# mlx) and the notices file deliberately does not pin exact versions, so this does NOT
# diff the resolved tree. Instead it enforces the one stable invariant: every dependency
# *declared* in setup/install.sh — the pip packages and the external CLI tools — must be
# named in THIRD-PARTY-NOTICES.md. That catches the real mistake: adding a dependency
# without documenting it. Refresh the version table from a real venv when it changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/setup/install.sh"
NOTICES="$ROOT/THIRD-PARTY-NOTICES.md"

[ -f "$NOTICES" ] || { echo "FAIL: $NOTICES not found"; exit 1; }

missing=0
note_has() { grep -qiF -- "$1" "$NOTICES"; }

# Top-level pip packages: tokens after `pip ... install` on each pip line, minus flags
# and the pip self-upgrade.
pip_pkgs="$(
  grep -E 'pip"? +install' "$INSTALL" \
    | sed -E 's/.*install//' \
    | tr ' \\' '\n\n' \
    | grep -E '^[A-Za-z]' \
    | grep -vxF 'pip' \
    | sort -u
)"

# External CLI tools from the `for t in ... ; do` availability check.
cli_tools="$(
  grep -E '^for t in ' "$INSTALL" \
    | sed -E 's/^for t in (.*); do.*/\1/' \
    | tr ' ' '\n' \
    | grep -vE '^$' \
    | sort -u
)"

echo "Checking THIRD-PARTY-NOTICES.md covers declared dependencies…"
for dep in $pip_pkgs $cli_tools; do
  if note_has "$dep"; then
    echo "  ok:      $dep"
  else
    echo "  MISSING: $dep  — add it to THIRD-PARTY-NOTICES.md"
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo
  echo "THIRD-PARTY-NOTICES.md is out of date. Document the dependencies above,"
  echo "then refresh the version table from an installed venv if appropriate."
  exit 1
fi
echo "All declared dependencies are documented."
