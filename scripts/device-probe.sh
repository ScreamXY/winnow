#!/bin/bash
# Runs a JavaScript file in Winnow's page on a connected device and prints the answer.
# Needs a Debug build of Winnow ("Winnow Dev") that is open on the device. See App/DebugProbe.swift.
#
#   scripts/device-probe.sh <device name or UDID> <script.js> [--snapshot]
#
# The script is the body of an async function in Winnow's script world, so it can `return` a value.
# Return page structure, not people's names or posts. With --snapshot, the app also saves a picture of
# the web view to build/probe/snapshot.png.
set -euo pipefail

device="${1:?device name or UDID}"
script="${2:?script file}"
snapshot="${3:-}"
bundle="com.screamxy.winnow"
out="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/build/probe"
upload="$(mktemp -d)"
trap 'rm -rf "$upload"' EXIT
mkdir -p "$out" "$upload/probe"

copy_from() {
    xcrun devicectl device copy from --device "$device" --domain-type appDataContainer \
        --domain-identifier "$bundle" --source "Documents/probe/$1" --destination "$out/$1" >/dev/null 2>&1
}

rm -f "$out/response.json" "$out/snapshot.png"
copy_from response.json || true
before="$(cat "$out/response.json" 2>/dev/null || true)"

cp "$script" "$upload/probe/request.js"
if [ "$snapshot" = "--snapshot" ]; then
    touch "$upload/probe/snapshot.request"
fi
# Copy the whole folder: copying a single file to Documents/probe would replace the folder.
xcrun devicectl device copy to --device "$device" --domain-type appDataContainer --domain-identifier "$bundle" \
    --source "$upload/probe" --destination Documents/probe >/dev/null

for _ in $(seq 1 40); do
    sleep 3
    copy_from response.json || continue
    if [ "$(cat "$out/response.json")" != "$before" ]; then
        if [ "$snapshot" = "--snapshot" ]; then
            sleep 2
            copy_from snapshot.png || echo "No snapshot yet." >&2
        fi
        cat "$out/response.json"
        exit 0
    fi
done
echo "No answer after 2 minutes. Is Winnow Dev open and in front on the device?" >&2
exit 1
