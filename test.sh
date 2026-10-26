#!/bin/bash
# Runs the Swift tests. With only the Command Line Tools installed, `swift test` does not find their
# Testing.framework on its own, so pass its location explicitly. With Xcode no extra flags are needed.
set -euo pipefail
cd "$(dirname "$0")"
DEVELOPER_DIR="$(xcode-select -p)"
ARGS=()
if [[ "$DEVELOPER_DIR" == *CommandLineTools* ]]; then
    FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
    LIBS="$DEVELOPER_DIR/Library/Developer/usr/lib"
    ARGS=(-Xswiftc -F -Xswiftc "$FRAMEWORKS" -Xlinker -F -Xlinker "$FRAMEWORKS"
          -Xlinker -rpath -Xlinker "$FRAMEWORKS" -Xlinker -rpath -Xlinker "$LIBS")
fi
swift test ${ARGS[@]+"${ARGS[@]}"} "$@"
