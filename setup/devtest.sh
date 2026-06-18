#!/bin/bash
# Dev/test helper: toggle a recording while forcing a specific input/output source,
# so live device tests use one stable, pre-approvable command prefix.
#
# Usage:
#   devtest.sh start <input_source> <output_source>   # e.g. start jabra jabra
#   devtest.sh stop
#
# <source> is jabra|builtin|bluetooth|auto (see src/config.sh). record.sh is a
# toggle, so "stop" just calls it again; the env only matters on "start".
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$1" = "start" ]; then
  export MEETINGS_INPUT_SOURCE="${2:-auto}" MEETINGS_OUTPUT_SOURCE="${3:-auto}"
fi
exec bash "$ROOT/src/bin/record.sh"
