#!/bin/sh
# Fake CLI fixture: spawns a grandchild in the background, then hangs itself.
# Used to prove the runner's process-group termination reaches both the
# direct child and its own descendant, not just the immediate Port process.
#
# Both PIDs are written to `pids` in the runner-provided scratch dir (our cwd)
# so tests can assert on exact PIDs. Matching a pattern like "sleep 300" with
# pgrep would also match unrelated processes on a shared machine, which makes
# the leak assertions both flaky and weak.
sleep 300 &
grandchild=$!
printf 'child=%s\ngrandchild=%s\n' "$$" "$grandchild" > pids
echo "grandchild_pid=$grandchild"
sleep 300
