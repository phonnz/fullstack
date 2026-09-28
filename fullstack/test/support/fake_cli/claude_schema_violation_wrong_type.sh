#!/bin/sh
# Fake claude CLI fixture: structured_output has a non-string, non-null
# value (a number) for one field.
cat <<'JSON'
{"result":"","is_error":false,"subtype":"success","structured_output":{"country":"Chile","city":null,"business_market":null,"initial_budget":42,"final_product_proposal":null,"product_price":null}}
JSON
exit 0
