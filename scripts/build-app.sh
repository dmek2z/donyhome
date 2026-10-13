#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
dony_sdk_path="$(zsh scripts/sdk-path.sh)"
dony_configuration="${DONY_BUILD_CONFIGURATION:-release}"
swift build --sdk "$dony_sdk_path" -j 2 -c "$dony_configuration"
dony_bin_path="$(swift build --sdk "$dony_sdk_path" -c "$dony_configuration" --show-bin-path)"
dony_bundle="$PWD/build/DonyClean.app"
mkdir -p "$dony_bundle/Contents/MacOS" "$dony_bundle/Contents/Resources/Fonts" "$dony_bundle/Contents/Resources/Icons" build/DonyClean.iconset
cp "$dony_bin_path/DonyClean" "$dony_bundle/Contents/MacOS/DonyClean.next"
mv -f "$dony_bundle/Contents/MacOS/DonyClean.next" "$dony_bundle/Contents/MacOS/DonyClean"
cp Resources/Info.plist "$dony_bundle/Contents/Info.plist"
cp Resources/DonyLogo.png "$dony_bundle/Contents/Resources/DonyLogo.png"
cp Resources/Fonts/* "$dony_bundle/Contents/Resources/Fonts/"
cp Resources/Icons/*.pdf Resources/Icons/LICENSE "$dony_bundle/Contents/Resources/Icons/"
for dony_icon_size in 16 32 128 256 512; do
    sips -z "$dony_icon_size" "$dony_icon_size" Resources/DonyLogo.png --out "build/DonyClean.iconset/icon_${dony_icon_size}x${dony_icon_size}.png" >/dev/null
    dony_retina_size=$((dony_icon_size * 2))
    sips -z "$dony_retina_size" "$dony_retina_size" Resources/DonyLogo.png --out "build/DonyClean.iconset/icon_${dony_icon_size}x${dony_icon_size}@2x.png" >/dev/null
done
iconutil -c icns build/DonyClean.iconset -o "$dony_bundle/Contents/Resources/DonyClean.icns"
codesign --force --deep --sign - "$dony_bundle"
codesign --verify --deep --strict "$dony_bundle"
print -r -- "Built: $dony_bundle"
