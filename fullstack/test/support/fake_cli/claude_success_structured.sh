#!/bin/sh
# Fake claude CLI fixture: valid success envelope, structured_output mode.
# The structured payload comes from CLAUDE_FAKE_STRUCTURED_OUTPUT (a JSON
# object) so tests can exercise ANY supplied schema; the default is the
# eleven ExtractionOutput fields with mixed known/null values.
if [ -n "$CLAUDE_FAKE_STRUCTURED_OUTPUT" ]; then
  payload="$CLAUDE_FAKE_STRUCTURED_OUTPUT"
else
  payload='{"country":"Argentina","city":null,"business_market":"coffee shop","initial_budget":"5000 USD","final_product_proposal":null,"product_price":null,"team_size":null,"current_tools_systems":null,"repetitive_processes_pain_points":null,"digital_maturity":null,"metrics_baselines":null}'
fi
printf '{"result":"","is_error":false,"subtype":"success","structured_output":%s}\n' "$payload"
exit 0
