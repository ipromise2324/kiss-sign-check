#!/bin/bash
# Records into test/sourcify/ every Sourcify answer check.sh asks for while it decodes each fixture, so the tests
# run offline. Needs the network. Usage: /bin/bash test/record-sourcify.sh
set -euo pipefail

TEST=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
rm -rf "$TEST/sourcify"
mkdir "$TEST/sourcify"

for fixture in "$TEST"/fixtures/*.json; do
  printf 'SAFE=%s\nSAFE_VERSION=1.4.1\n' "$(jq -r '(.results[0] // .).safe' "$fixture")" > "$WORK/config"
  CHECK_CONFIG="$WORK/config" CHECK_KNOWN="$TEST/known-addresses.txt" CHECK_OUT="$WORK/out" CHECK_SOURCIFY_SAVE="$TEST/sourcify" \
    /bin/bash "$TEST/../check.sh" --file "$fixture" > "$WORK/log" 2>&1 || true
  if grep -q 'from Sourcify' "$WORK/log"; then grep 'from Sourcify' "$WORK/log"; exit 1; fi
  printf '%-50s %s\n' "$(basename "$fixture")" "$(grep -c . <<<"$(ls "$TEST/sourcify")") answers so far"
done
