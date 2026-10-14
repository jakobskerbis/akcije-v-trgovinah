#!/usr/bin/env bash
# Zgradi aplikacijo za simulator in posname zaslone na najnovejšem iPhonu in iPadu Pro 13".
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-screenshots}"
mkdir -p "$OUT"
BUNDLE=com.jakobskerbis.akcijesi

xcodebuild build -project AkcijeSI.xcodeproj -scheme AkcijeSI -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet
APP=$(find build/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "*.app" | head -1)

shoot() { # $1 device-udid $2 file $3.. launch args
  local udid=$1 file=$2; shift 2
  xcrun simctl terminate "$udid" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$BUNDLE" -demo "$@" >/dev/null
  sleep 9
  xcrun simctl io "$udid" screenshot "$OUT/$file" >/dev/null
  echo "posnetek: $OUT/$file"
}

prepare() { # $1 udid
  local udid=$1
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularBars 4 --dataNetwork wifi >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP"
  # dovoli obvestila brez dialoga (če je podprto)
  xcrun simctl privacy "$udid" grant notifications "$BUNDLE" >/dev/null 2>&1 || true
}

IFS='|' read -r IPHONE_NAME IPHONE <<<"$(python3 scripts/pick_simulators.py iphone)"
IFS='|' read -r IPAD_NAME IPAD <<<"$(python3 scripts/pick_simulators.py ipad)"
echo "iPhone: $IPHONE_NAME, iPad: $IPAD_NAME"
echo "$IPHONE_NAME" > "$OUT/iphone.txt"; echo "$IPAD_NAME" > "$OUT/ipad.txt"

prepare "$IPHONE"
xcrun simctl ui "$IPHONE" appearance light
shoot "$IPHONE" iphone-1-izpostavljeno.png -section highlights
shoot "$IPHONE" iphone-2-kategorije.png -section categories
shoot "$IPHONE" iphone-3-kuponi.png -section coupons
shoot "$IPHONE" iphone-4-moj-seznam.png -section myList
shoot "$IPHONE" iphone-5-vodic.png -section guide
shoot "$IPHONE" iphone-6-dom-in-vrt.png -section highlights -storeSection dom
xcrun simctl ui "$IPHONE" appearance dark
shoot "$IPHONE" iphone-7-temni-nacin.png -section highlights

prepare "$IPAD"
xcrun simctl ui "$IPAD" appearance light
shoot "$IPAD" ipad-1-lezece-izpostavljeno.png -section highlights -selectFirst -landscape
shoot "$IPAD" ipad-2-lezece-kategorija.png -section categories -landscape
shoot "$IPAD" ipad-3-pokoncno.png -section highlights -selectFirst -portrait
xcrun simctl ui "$IPAD" appearance dark
shoot "$IPAD" ipad-4-temni-nacin.png -section highlights -selectFirst -landscape
