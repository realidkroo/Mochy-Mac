#!/bin/sh
# builds Mochy.app for intel macs into build/, release by default, pass Debug for a quicker build
set -e
cd "$(dirname "$0")/.."

CONFIG="${1:-Release}"
xcodebuild -project Mochy.xcodeproj -target Mochy -configuration "$CONFIG" \
    SYMROOT="$PWD/build" ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO -quiet build

rm -rf build/Mochy.app
cp -R "build/$CONFIG/Mochy.app" build/Mochy.app
echo "built $PWD/build/Mochy.app"
