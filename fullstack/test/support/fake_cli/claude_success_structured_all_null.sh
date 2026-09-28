#!/bin/sh
# Fake claude CLI fixture: valid success envelope, structured_output with
# every field null (must still be VALID per plan line 275).
cat <<'JSON'
{"result":"","is_error":false,"subtype":"success","structured_output":{"country":null,"city":null,"business_market":null,"initial_budget":null,"final_product_proposal":null,"product_price":null}}
JSON
exit 0
