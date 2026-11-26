#!/bin/sh
# Fast checks that also run on GitHub: lint, format, core tests and a simulator build.
set -eu

cd "$(dirname "$0")/.."

swiftlint lint --strict --no-cache
xcrun swift-format lint --strict --recursive App Sources Tests UITests scripts Package.swift
swift test
"$(dirname "$0")/xcodegen.sh"
xcodebuild -project Winnow.xcodeproj -scheme Winnow \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build/CheckDerivedData CODE_SIGNING_ALLOWED=NO build
