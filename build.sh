#!/bin/bash
# Builds "Critter Crew.app" into ./build
# ./build.sh --release also makes a universal (Apple silicon + Intel) build
# and zips it to build/CritterCrew.zip for a GitHub Release.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Critter Crew.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

if [ "${1:-}" = "--release" ]; then
    swift build -c release --arch arm64 --arch x86_64
    cp .build/apple/Products/Release/CritterCrew "$APP/Contents/MacOS/CritterCrew"
else
    swift build -c release
    cp .build/release/CritterCrew "$APP/Contents/MacOS/CritterCrew"
fi

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null

if [ "${1:-}" = "--release" ]; then
    rm -f build/CritterCrew.zip
    ditto -c -k --sequesterRsrc --keepParent "$APP" build/CritterCrew.zip
    echo "Zipped build/CritterCrew.zip"
fi

echo "Built $APP"
