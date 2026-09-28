#!/bin/sh
# Fake CLI fixture: prints far more bytes than any reasonable test-configured
# max_output_bytes limit, then exits successfully. Used to prove stdout
# overflow is detected and reported as an error even on a clean exit.
i=0
while [ "$i" -lt 5000 ]; do
  echo "0123456789012345678901234567890123456789012345678901234567890123456789"
  i=$((i + 1))
done
exit 0
