#!/bin/bash
# Writes NOTARY_KEY_P8 to the given path as the .p8 file's text.
# The secret may hold the file's text (BEGIN/END lines) or its base64 (the desktop bench's form).
set -euo pipefail
OUT="$1"
if printf '%s' "$NOTARY_KEY_P8" | grep -q -- "-----BEGIN"; then
  printf '%s\n' "$NOTARY_KEY_P8" > "$OUT"
else
  printf '%s' "$NOTARY_KEY_P8" | tr -d ' \r\n' | base64 --decode > "$OUT"
fi
grep -q -- "-----BEGIN PRIVATE KEY-----" "$OUT" || { echo "::error title=Notarization::NOTARY_KEY_P8 is neither the .p8 text nor its base64"; exit 1; }
chmod 600 "$OUT"
