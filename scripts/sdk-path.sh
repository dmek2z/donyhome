#!/bin/zsh
set -euo pipefail
if [[ -n "${DONY_SDK_PATH:-}" ]]; then
    print -r -- "$DONY_SDK_PATH"
elif [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    print -r -- /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
else
    xcrun --show-sdk-path
fi
