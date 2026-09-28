#!/bin/sh
# Fake CLI fixture: echoes each argv element on its own line, verbatim. Used
# to prove argv elements reach the child process literally, with no shell
# interpretation of metacharacters (;, $(...), backticks, embedded spaces).
for arg in "$@"; do
  echo "ARG:[$arg]"
done
exit 0
