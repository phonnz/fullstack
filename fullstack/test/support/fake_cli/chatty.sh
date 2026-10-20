#!/bin/sh
# Fake CLI fixture: prints continuously and never exits on its own. Used to
# prove the runner's deadline is monotonic and NOT reset by incoming output
# chunks (a chatty process must still time out).
#
# Writes its own pid to `pids` in the runner-provided scratch dir (our cwd) so
# the test can assert on an exact pid. A pgrep pattern would also match the
# test harness's own command line, which makes such assertions self-matching
# and unreliable.
printf 'child=%s\n' "$$" > pids
while true; do
  echo "chunk"
  sleep 0.05
done
