#!/bin/sh
# Fake claude CLI fixture: success envelope but empty result (text mode
# must reject this).
cat <<'JSON'
{"result":"","is_error":false,"subtype":"success"}
JSON
exit 0
