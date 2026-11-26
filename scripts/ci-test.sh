#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ci
result_dir=$(mktemp -d build/ci/local.XXXXXX)

run_tests() {
    local name="$1" scheme="$2" destination="$3"
    shift 3
    xcodebuild -project Winnow.xcodeproj -scheme "$scheme" \
        -destination "$destination" -destination-timeout 30 \
        -derivedDataPath build/CheckDerivedData \
        -resultBundlePath "$result_dir/$name.xcresult" \
        -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 120 \
        -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO "$@" test \
        2>&1 | tee "$result_dir/$name.log"
}

device="${1:-}"
case "$device" in
    iPhone|iPad) scheme=Winnow; platform='iOS Simulator' ;;
    *) echo "Usage: bash scripts/ci-test.sh iPhone|iPad [destination]" >&2; exit 1 ;;
esac

destination="${2:-}"
if [ -z "$destination" ]; then
    simulator_id=$(xcrun simctl list devices available --json | python3 -c '
import json, re, sys
kind = sys.argv[1]
os_name = "iOS"
prefix = kind
devices = json.load(sys.stdin)["devices"]
runtimes = sorted((r for r in devices if "SimRuntime." + os_name + "-" in r),
                  key=lambda r: tuple(map(int, re.findall(r"\d+", r))), reverse=True)
for runtime in runtimes:
    matches = [d for d in devices[runtime] if d.get("isAvailable") and d["name"].startswith(prefix)]
    if matches:
        print(matches[0]["udid"])
        sys.exit(0)
sys.exit("No available " + kind + " simulator; install a runtime or pass a destination")
' "$device")
    destination="platform=$platform,id=$simulator_id"
fi

run_tests "$device" "$scheme" "$destination"
