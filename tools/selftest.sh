#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
source ${0:A:h}/test-app.sh
store=/tmp/AntHill-self.store
rm -f $store $store-shm $store-wal $store-shop-checks.json
APP_STORE=$store $app --selftest
