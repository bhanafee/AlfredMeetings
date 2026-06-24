#!/bin/bash
# Drift guard for THIRD-PARTY-NOTICES.md.
#
# Rebuilding the full venv in CI is impractical (multi-GB PyTorch, Apple-Silicon-only
# mlx) and the notices file deliberately does not pin exact versions, so this does NOT
# diff the resolved tree. Instead it enforces the one stable invariant: every dependency
# *declared* in setup/install.sh — the pip packages and the external CLI tools — must be
# named in THIRD-PARTY-NOTICES.md. That catches the real mistake: adding a dependency
# without documenting it.
#
# Usage:
#   check-notices.sh             Verify coverage (default; used by CI).
#   check-notices.sh --refresh   Regenerate the full version table in-place from the
#                                installed venv. Run this on a Mac after install.sh
#                                resolves new versions, then commit the result.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$ROOT/setup/install.sh"
NOTICES="$ROOT/THIRD-PARTY-NOTICES.md"

[ -f "$NOTICES" ] || { echo "FAIL: $NOTICES not found"; exit 1; }

# --- --refresh: regenerate the generated table block from the live venv -------------
if [ "${1:-}" = "--refresh" ]; then
  VENV="${MEETINGS_SUPPORT:-$HOME/Library/Application Support/AlfredMeetings}/venv"
  PY="$VENV/bin/python"
  [ -x "$PY" ] || { echo "FAIL: no venv at $VENV — run setup/install.sh first."; exit 1; }
  echo "Refreshing the dependency table from $VENV …"
  NOTICES="$NOTICES" "$PY" - <<'PY'
import importlib.metadata as m, os, re, sys

SPDX = {
    "MIT License": "MIT", "Apache Software License": "Apache-2.0",
    "Apache License 2.0": "Apache-2.0", "Apache 2.0": "Apache-2.0",
    "BSD License": "BSD-3-Clause", "BSD": "BSD-3-Clause",
    "3-Clause BSD License": "BSD-3-Clause",
    "Python Software Foundation License": "PSF-2.0",
    "ISC License (ISCL)": "ISC", "Mozilla Public License 2.0 (MPL 2.0)": "MPL-2.0",
    "MIT-CMU": "MIT-CMU",
}
# The pyannote suite + torchcodec ship no license metadata; document their known SPDX.
KNOWN = {
    "pyannote-audio": "MIT (see project)", "pyannote-core": "MIT (see project)",
    "pyannote-metrics": "MIT (see project)", "pyannote-database": "MIT (see project)",
    "pyannote-pipeline": "MIT (see project)", "pyannoteai-sdk": "MIT",
    "torchcodec": "BSD-3-Clause",
}

def lic(d):
    n = d.metadata["Name"]
    if n in KNOWN:
        return KNOWN[n]
    le = d.metadata.get("License-Expression")
    if le:
        return le.strip()
    cls = [v.split("::")[-1].strip() for k, v in d.metadata.items()
           if k == "Classifier" and v.startswith("License")]
    if cls:
        return "; ".join(SPDX.get(c, c) for c in dict.fromkeys(cls))
    l = (d.metadata.get("License") or "").strip().split("\n")[0]
    return SPDX.get(l, l[:30]) if l else "see project"

rows = sorted(((d.metadata["Name"], d.version, lic(d)) for d in m.distributions()),
              key=lambda r: r[0].lower())
table = ["| Package | Version | License |", "|---|---|---|"]
table += [f"| `{n}` | {v} | {l} |" for n, v, l in rows]
block = ("<!-- BEGIN GENERATED TABLE — do not edit by hand; run "
         "`setup/check-notices.sh --refresh` -->\n"
         + "\n".join(table) + "\n<!-- END GENERATED TABLE -->")

path = os.environ["NOTICES"]
text = open(path, encoding="utf-8").read()
new, n = re.subn(
    r"<!-- BEGIN GENERATED TABLE.*?<!-- END GENERATED TABLE -->",
    lambda _: block, text, count=1, flags=re.S)
if n != 1:
    sys.exit("FAIL: GENERATED TABLE markers not found in THIRD-PARTY-NOTICES.md")
open(path, "w", encoding="utf-8").write(new)
print(f"  wrote {len(rows)} packages")
PY
  echo "Done. Review the diff and commit."
  exit 0
fi

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
