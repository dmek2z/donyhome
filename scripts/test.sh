#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
dony_developer_dir="$(xcode-select -p)"
dony_sdk_path="$(zsh scripts/sdk-path.sh)"
dony_testing_plugin="$dony_developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
dony_testing_frameworks="$dony_developer_dir/Library/Developer/Frameworks"
if [[ -f "$dony_testing_plugin" ]]; then
    swift test --build-system native --sdk "$dony_sdk_path" -j 2 --disable-xctest \
        -Xswiftc -F -Xswiftc "$dony_testing_frameworks" \
        -Xswiftc -load-plugin-library -Xswiftc "$dony_testing_plugin" \
        -Xlinker -F -Xlinker "$dony_testing_frameworks" \
        -Xlinker -rpath -Xlinker "$dony_testing_frameworks"
else
    swift test --sdk "$dony_sdk_path" --disable-xctest
fi
