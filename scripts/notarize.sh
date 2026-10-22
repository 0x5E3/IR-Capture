#!/bin/bash
# Notarizes a signed .zip or .dmg with Apple and staples the ticket.
#   scripts/notarize.sh <file> [app-to-staple]
# Needs an App Store Connect API key: NOTARY_KEY_PATH (the .p8 file), NOTARY_KEY_ID, NOTARY_ISSUER_ID.
# For a .zip, Apple can't staple the zip itself, so pass the .app to staple instead.
set -euo pipefail
FILE="$1"; STAPLE="${2:-$1}"
: "${NOTARY_KEY_PATH:?}" "${NOTARY_KEY_ID:?}" "${NOTARY_ISSUER_ID:?}"
OUT="$(mktemp)"
if ! xcrun notarytool submit "$FILE" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
       --wait --timeout 30m --output-format json | tee "$OUT"; then
  echo "::error title=Notarization::notarytool failed"; exit 1
fi
ID="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("id",""))' "$OUT")"
STATUS="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "$OUT")"
if [ "$STATUS" != "Accepted" ]; then
  xcrun notarytool log "$ID" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" || true
  echo "::error title=Notarization::Apple returned $STATUS for $FILE"; exit 1
fi
xcrun stapler staple "$STAPLE"
xcrun stapler validate "$STAPLE"
spctl --assess --type execute --verbose "$STAPLE" 2>/dev/null || spctl --assess --type open --context context:primary-signature --verbose "$STAPLE" || true
echo "notarized and stapled $STAPLE"
