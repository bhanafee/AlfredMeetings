#!/bin/bash
# Alfred Script Filter for the `notes` keyword. Emits the three preset modes, plus
# a "Custom" item built from whatever the user has typed after the keyword.
# The selected item's `arg` is passed to notes_run.sh.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
Q="$*"

jq -n --arg q "$Q" '{
  items: ([
    {title:"Meeting minutes", subtitle:"Minutes, decisions, and action items", arg:"minutes"},
    {title:"Summary",         subtitle:"Concise overview and key points",      arg:"summary"},
    {title:"Clean up",        subtitle:"Remove filler; keep all content",      arg:"clean"}
  ] + (if ($q | length) == 0 then []
       else [{title:("Custom: " + $q),
              subtitle:"Run this instruction against the transcript",
              arg:("custom\t" + $q)}]
       end))
}'
