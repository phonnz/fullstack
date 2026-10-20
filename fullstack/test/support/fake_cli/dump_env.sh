#!/bin/sh
# Fake CLI fixture: dumps its full environment to stdout, one VAR=value per
# line. Used to prove env allowlisting: only explicitly configured variables
# survive, and inherited/ambient variables (including secrets) are absent.
env
exit 0
