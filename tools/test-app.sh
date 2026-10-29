# Sourced by snap.sh and selftest.sh. A running AntHill (menu bar app) keeps a
# second copy with the same bundle id from showing windows, so tests run a copy
# with its own id. Sets $app to the test binary.
test_app=/tmp/AntHill-test.app
rm -rf $test_app ~/Library/Saved\ Application\ State/com.sebkrupa.anthill.testrun.savedState
cp -R /Applications/AntHill.app $test_app
plutil -replace CFBundleIdentifier -string com.sebkrupa.anthill.testrun $test_app/Contents/Info.plist
codesign --force --sign - $test_app 2>/dev/null
app=$test_app/Contents/MacOS/AntHill
