#!/bin/sh
# Fake codex fixture: writes a valid all-six-key extraction JSON object (some
# string, some null) to the "-o" output file and exits 0.
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
{"country":"Argentina","city":null,"business_market":"software","initial_budget":"5000","final_product_proposal":null,"product_price":null}
JSON
fi

exit 0
