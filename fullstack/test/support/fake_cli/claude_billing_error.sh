#!/bin/sh
# Fake claude CLI fixture: THE regression fixture. Exit status 0, but
# is_error true / api_error_status 400 / result carries the billing message.
# Must NEVER be treated as {:ok, "Credit balance is too low"}.
cat <<'JSON'
{"result":"Credit balance is too low","is_error":true,"api_error_status":400,"subtype":"error","session_id":"sess_123"}
JSON
exit 0
