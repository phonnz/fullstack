#!/bin/sh
# Fake claude CLI fixture: structured_output has an extra, unexpected key.
cat <<'JSON'
{"result":"","is_error":false,"subtype":"success","structured_output":{"country":"Chile","city":null,"business_market":null,"initial_budget":null,"final_product_proposal":null,"product_price":null,"unexpected":"value"}}
JSON
exit 0
