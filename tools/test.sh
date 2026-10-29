#!/bin/zsh
# Runs the unit tests. Extra arguments go to swift test, like --filter NetLock.
set -euo pipefail
here=${0:A:h:h}
extra=()
# shortcut: Command Line Tools 27 lack the SwiftUI macro plugin and keep the Testing one in a subfolder SwiftPM skips, so build against the 26 SDK and pass that folder; drop this once Xcode is installed.
if [[ "$(xcode-select -p)" == */CommandLineTools ]]; then
  [[ -n "${SDKROOT:-}" ]] || export SDKROOT=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk 2>/dev/null | tail -1)
  plugins=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
  [[ -d $plugins ]] && extra=(-Xswiftc -plugin-path -Xswiftc $plugins)
fi
swift test --package-path "$here" --scratch-path ~/Library/Developer/AntHill/test-build "${extra[@]}" "$@"
