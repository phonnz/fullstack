#!/bin/sh
# Fake codex fixture: writes JSON that is well-formed but violates the fixed
# extraction schema (missing a required key, plus an extra key) to the "-o"
# output file, and exits 0.
output_file=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    output_file="$arg"
  fi
  prev="$arg"
done

if [ -n "$output_file" ]; then
  cat > "$output_file" <<'JSON'
{"country":"Argentina","city":null,"business_market":"software","initial_budget":"5000","extra_key":"nope"}
JSON
fi

exit 0
