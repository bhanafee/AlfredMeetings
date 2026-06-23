#!/bin/bash
# Dev/test helper: toggle a recording while forcing a specific microphone source and
# optional Them-app scope, so live device tests use one stable, pre-approvable prefix.
#
# Usage:
#   devtest.sh start <mic_source> [them_app]   # e.g. start jabra   |   start builtin zoom.us
#   devtest.sh stop
#
# <mic_source> is jabra|builtin|bluetooth|auto (see src/config.sh). [them_app], if given,
# scopes the tap to that app (else all system audio). record.sh is a toggle, so "stop"
# just calls it again; the env only matters on "start".
set -e
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$1" = "start" ]; then
  export MEETINGS_INPUT_SOURCE="${2:-auto}"
  [ -n "$3" ] && export MEETINGS_THEM_APP="$3"
fi
exec bash "$ROOT/src/bin/record.sh"
