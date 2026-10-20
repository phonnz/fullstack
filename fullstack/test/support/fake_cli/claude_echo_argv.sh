#!/bin/sh
# Fake claude CLI fixture: writes argv, one element per line prefixed
# "ARG:[...]", to a sibling file "argv.log" in the cwd (the Runner's private
# scratch dir), then emits ONLY a valid success JSON envelope on stdout.
# Splitting the two channels lets tests both assert exact argv shape (by
# reading argv.log via a direct Runner.run/3 call before cleanup removes the
# scratch dir) and exercise the adapter's own stdout JSON parsing without the
# argv echo corrupting it.
for arg in "$@"; do
  echo "ARG:[$arg]" >> argv.log
done
echo '{"result":"ok","is_error":false,"subtype":"success"}'
exit 0
