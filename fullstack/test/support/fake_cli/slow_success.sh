#!/bin/sh
# Fake CLI fixture: sleeps briefly then succeeds. Used for concurrency tests
# where several runner calls must overlap in time and remain independent.
sleep 0.2
echo "slow result: $1"
exit 0
