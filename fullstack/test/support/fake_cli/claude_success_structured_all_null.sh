#!/bin/sh
# Fake claude CLI fixture: valid success envelope, structured_output with
# every field null (must still be VALID per plan line 275).
cat <<'JSON'
{"result":"","is_error":false,"subtype":"success","structured_output":{"country":null,"city":null,"business_market":null,"initial_budget":null,"final_product_proposal":null,"product_price":null,"team_size":null,"current_tools_systems":null,"repetitive_processes_pain_points":null,"digital_maturity":null,"metrics_baselines":null}}
JSON
exit 0
