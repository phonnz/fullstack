#!/bin/sh
# Fake codex fixture: reproduces the historical noisy-but-successful codex
# run — stdout carries session/hook noise AND the literal string
# "ERROR: Reconnecting... 2/5" while the process still exits 0 and writes a
# valid "-o" file. Proves stdout content is never inspected for success.
output_file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    output_file="$arg"
  fi
  prev="$arg"
done

echo "session id: 01a0e34b-fake-session"
echo "warning: Codex's Linux sandbox uses bubblewrap and needs access to create user namespaces."
echo "hook: SessionStart"
echo "hook: UserPromptSubmit Completed"
echo "ERROR: Reconnecting... 2/5"
echo "codex"

if [ -n "$output_file" ]; then
  printf 'PONG\n' > "$output_file"
fi

echo "tokens used"
echo "27,124"
exit 0
