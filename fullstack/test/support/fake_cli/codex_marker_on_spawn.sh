#!/bin/sh
# Fake codex fixture: if actually spawned, creates a marker file in cwd (the
# Runner-provided scratch dir). Used to prove a role/message-validation
# rejection short-circuits before any subprocess is ever spawned.
touch "codex_marker_on_spawn.touched"
exit 0
