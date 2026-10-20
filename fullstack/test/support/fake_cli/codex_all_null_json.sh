#!/bin/sh
# Fake codex fixture: writes a valid all-null extraction JSON object to the
# "-o" output file and exits 0 — proves all-null structured output is
# accepted, not treated as empty/missing.
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
{"country":null,"city":null,"business_market":null,"initial_budget":null,"final_product_proposal":null,"product_price":null}
JSON
fi

exit 0
