#!/bin/sh
# Fake claude CLI fixture: success envelope, text-mode result present, but
# NO structured_output field at all. Structured mode must reject this
# WITHOUT falling back to result.
cat <<'JSON'
{"result":"some incidental text","is_error":false,"subtype":"success"}
JSON
exit 0
