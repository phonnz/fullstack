#!/bin/sh
# Fake claude CLI fixture: valid success envelope, structured_output mode,
# all six ExtractionOutput fields present with mixed known/null values.
cat <<'JSON'
{"result":"","is_error":false,"subtype":"success","structured_output":{"country":"Argentina","city":null,"business_market":"coffee shop","initial_budget":"5000 USD","final_product_proposal":null,"product_price":null}}
JSON
exit 0
