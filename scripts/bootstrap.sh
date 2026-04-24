#!/usr/bin/env bash
#
# Bootstraps a fresh checkout of dispad: installs XcodeGen if needed,
# then regenerates the two Xcode projects from their project.yml specs.
#
# Run this after cloning, and whenever project.yml changes.

set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "XcodeGen not found. Installing via Homebrew..."
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is required. Install it from https://brew.sh and re-run this script."
        exit 1
    fi
    brew install xcodegen
fi

echo "Generating DispadHost.xcodeproj..."
(cd DispadHost && xcodegen generate)

echo "Generating DispadClient.xcodeproj..."
(cd DispadClient && xcodegen generate)

echo
echo "Done. Open the projects in Xcode:"
echo "  open DispadHost/DispadHost.xcodeproj"
echo "  open DispadClient/DispadClient.xcodeproj"
