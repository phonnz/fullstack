#!/bin/sh
# Fake claude CLI fixture: valid success envelope, structured_output mode,
# all eleven ExtractionOutput fields present with mixed known/null values.
cat <<'JSON'
{"result":"","is_error":false,"subtype":"success","structured_output":{"country":"Argentina","city":null,"business_market":"coffee shop","initial_budget":"5000 USD","final_product_proposal":null,"product_price":null,"team_size":null,"current_tools_systems":null,"repetitive_processes_pain_points":null,"digital_maturity":null,"metrics_baselines":null}}
JSON
exit 0
