#!/bin/bash
# Builds "Critter Crew.app" into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/Critter Crew.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CritterCrew "$APP/Contents/MacOS/CritterCrew"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
