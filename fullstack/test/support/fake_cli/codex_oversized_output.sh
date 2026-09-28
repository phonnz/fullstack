#!/bin/sh
# Fake codex fixture: writes an "-o" output file larger than the adapter's
# @max_output_bytes limit (well over 1MB) and exits 0.
output_file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    output_file="$arg"
  fi
  prev="$arg"
done

if [ -n "$output_file" ]; then
  # 2 MiB of 'A' characters, comfortably over a 1 MiB limit.
  head -c 2097152 /dev/zero | tr '\0' 'A' > "$output_file"
fi

exit 0
