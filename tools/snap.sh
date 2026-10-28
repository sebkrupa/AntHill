#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
set -u
store=/tmp/AntHill-test.store
shots=/tmp/AntHill-shots
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
source ${0:A:h}/test-app.sh
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal
rm -rf $shots
APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots $app
