#!/bin/zsh
# Builds AntHill and installs it to /Applications/AntHill.app.
# Build products live in ~/Library/Developer/AntHill, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
#        VERSION=1.2.0 ./build.sh   build that version (the release workflow does this)
set -euo pipefail
here=${0:A:h}
name="AntHill"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

app="/Applications/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
# The version: VERSION from the release workflow, else the newest git tag (v1.2.0 -> 1.2.0).
version=${VERSION:-$(git -C "$here" describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)}
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" -e "s/__VERSION__/${version#v}/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
# actool ships with Xcode only; without it tools/make_icns.swift draws a flat AppIcon.icns.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  if xcrun -f actool >/dev/null 2>&1; then
    car="$here/Resources/Assets.car"
    if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
      "$here/tools/make_icon.sh"
    fi
    cp -X "$car" "$app/Contents/Resources/"
  else
    rm -f "$here/Resources/Assets.car"
    icns="$here/Resources/AppIcon.icns"
    if [[ ! -f "$icns" || -n "$(find "$here/Icon/AppIcon.icon" "$here/tools/make_icns.swift" -newer "$icns" | head -1)" ]]; then
      swift "$here/tools/make_icns.swift"
    fi
  fi
  cp -X "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
# Network Lock runs this script as root.
cp -X "$here/Resources/netlock" "$app/Contents/Resources/"
# The menu bar icon, the app icon's ant as a template image.
cp -X "$here/Resources/MenuBarIcon.svg" "$app/Contents/Resources/"
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  sleep 0.5
  open "$app"
fi
