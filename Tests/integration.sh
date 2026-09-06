#!/bin/bash
# End-to-end run of the command line: a synthesised kit through every preset, offline, in an
# isolated home. No audio device is opened, so this runs on a headless runner.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="${BIN:-.build/debug/AmpMac}"
[ -x "$BIN" ] || swift build >/dev/null
export AMPMAC_HOME="$(mktemp -d)" AMPMAC_DEMO_DEVICES=1
trap 'rm -rf "$AMPMAC_HOME"' EXIT
pass=0; fail=0
check() { if eval "$2"; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; echo "  command: $2"; fi; }
check "version" '"$BIN" version | grep -q ampmac'
check "help exits 0" '"$BIN" help >/dev/null'
check "unknown command exits 64" '"$BIN" bogus >/dev/null 2>&1; [ $? = 64 ]'
check "presets lists at least thirty-six" '[ "$("$BIN" presets | wc -l | tr -d " ")" -ge 36 ]'
check "presets --json names Rock Room" '"$BIN" presets --json | grep -q "Rock Room"'
check "one preset prints its knobs" '"$BIN" presets Garage | grep -q "\"drive\" : 60"'
check "devices sees the demo interface" '"$BIN" devices | grep -q "Scarlett Solo USB"'
check "status picks input 2 on a Solo" '"$BIN" status --json | grep -q "\"inputChannel\" : 2"'
check "tone writes a kit" '"$BIN" tone "$AMPMAC_HOME/kit.wav" --seconds 2 >/dev/null && [ -s "$AMPMAC_HOME/kit.wav" ]'
for p in "Clean Kit" "Rock Room" "Seattle '91" "Gated '81" "Boom Bap" "Brushes" "Tight Metal" "Detroit '65" "Nashville" "Garage" "Juke Joint" "One Drop" "Dance"; do
  check "render $p" '"$BIN" render "$AMPMAC_HOME/kit.wav" "$AMPMAC_HOME/out.wav" --preset "'"$p"'" | grep -q "peak in"'
done
check "render rejects an unknown preset" '"$BIN" render "$AMPMAC_HOME/kit.wav" "$AMPMAC_HOME/out.wav" --preset nope >/dev/null 2>&1; [ $? = 1 ]'
check "render without files is a usage error" '"$BIN" render >/dev/null 2>&1; [ $? = 64 ]'
check "tone --chords writes C G Am F" '"$BIN" tone "$AMPMAC_HOME/chords.wav" --chords --loops 1 | grep -q "C G Am F"'
check "chords hears C major" '"$BIN" chords "$AMPMAC_HOME/chords.wav" | grep -q "Key: C major"'
check "chords --json carries chordmap's guitar section" '"$BIN" chords "$AMPMAC_HOME/chords.wav" --json | grep -q "\"guitar\""'
check "status names the chordmap version" '"$BIN" status --json | grep -q "\"chordmap\" : \"1."'
check "Info.plist carries the system audio string" 'grep -q NSAudioCaptureUsageDescription Info.plist'
# The microphone usage string: without it macOS kills the app the moment it opens the input.
check "Info.plist carries the microphone string" 'grep -q NSMicrophoneUsageDescription Info.plist'
if [ -d "/Applications/Amp for Mac.app" ]; then
  check "installed bundle carries the microphone string" 'grep -q NSMicrophoneUsageDescription "/Applications/Amp for Mac.app/Contents/Info.plist"'
fi
check "selftest is green" '"$BIN" selftest | tail -1 | grep -q " 0 failed"'
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
