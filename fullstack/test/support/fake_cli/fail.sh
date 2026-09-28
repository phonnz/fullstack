#!/bin/sh
# Fake CLI fixture: exits nonzero after printing to stdout and stderr.
echo "partial output before failure"
echo "some stderr diagnostic" >&2
exit 7
