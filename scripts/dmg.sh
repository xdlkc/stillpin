#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -d dist/Stillpin.app ]] || scripts/build.sh
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/stillpin-dmg.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/Stillpin.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname Stillpin -srcfolder "$STAGE" -ov -format UDZO dist/Stillpin-universal.dmg
shasum -a 256 dist/Stillpin-universal.dmg >> dist/SHA256SUMS.txt
