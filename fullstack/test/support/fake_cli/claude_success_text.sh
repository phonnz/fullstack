#!/bin/sh
# Fake claude CLI fixture: valid success envelope, text mode.
cat <<'JSON'
{"result":"Buenos Aires looks promising.","is_error":false,"subtype":"success"}
JSON
exit 0
