#!/usr/bin/env bash
set -euo pipefail
IOS_MIN="${IOS_MIN:-14.0}" MACOS_MIN="${MACOS_MIN:-13.0}" ./Scripts/build_xcframework.sh
swift build
