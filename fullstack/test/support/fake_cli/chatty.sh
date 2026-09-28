#!/bin/sh
# Fake CLI fixture: prints continuously and never exits on its own. Used to
# prove the runner's deadline is monotonic and NOT reset by incoming output
# chunks (a chatty process must still time out).
while true; do
  echo "chunk"
  sleep 0.05
done
