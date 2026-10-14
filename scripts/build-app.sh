#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
dony_sdk_path="$(zsh scripts/sdk-path.sh)"
dony_configuration="${DONY_BUILD_CONFIGURATION:-release}"
swift build --sdk "$dony_sdk_path" -j 2 -c "$dony_configuration"
dony_bin_path="$(swift build --sdk "$dony_sdk_path" -c "$dony_configuration" --show-bin-path)"
dony_bundle="$PWD/build/DonyHome.app"
mkdir -p "$dony_bundle/Contents/MacOS" "$dony_bundle/Contents/Resources/Fonts" "$dony_bundle/Contents/Resources/Icons" build/DonyHome.iconset
cp "$dony_bin_path/DonyHome" "$dony_bundle/Contents/MacOS/DonyHome.next"
mv -f "$dony_bundle/Contents/MacOS/DonyHome.next" "$dony_bundle/Contents/MacOS/DonyHome"
cp Resources/Info.plist "$dony_bundle/Contents/Info.plist"
cp Resources/DonyLogo.png "$dony_bundle/Contents/Resources/DonyLogo.png"
cp Resources/Fonts/* "$dony_bundle/Contents/Resources/Fonts/"
cp Resources/Icons/*.pdf Resources/Icons/LICENSE "$dony_bundle/Contents/Resources/Icons/"
for dony_resource_folder in Battery Clipboard ToolIcons; do
    if [[ -d "Resources/$dony_resource_folder" ]]; then
        ditto "Resources/$dony_resource_folder" "$dony_bundle/Contents/Resources/$dony_resource_folder"
    fi
done
swift -sdk "$dony_sdk_path" scripts/app-icon.swift Resources/DonyLogo.png build/DonyAppIcon.png
for dony_icon_size in 16 32 128 256 512; do
    sips -z "$dony_icon_size" "$dony_icon_size" build/DonyAppIcon.png --out "build/DonyHome.iconset/icon_${dony_icon_size}x${dony_icon_size}.png" >/dev/null
    dony_retina_size=$((dony_icon_size * 2))
    sips -z "$dony_retina_size" "$dony_retina_size" build/DonyAppIcon.png --out "build/DonyHome.iconset/icon_${dony_icon_size}x${dony_icon_size}@2x.png" >/dev/null
done
iconutil -c icns build/DonyHome.iconset -o "$dony_bundle/Contents/Resources/DonyHome.icns"
if xattr -p com.apple.FinderInfo "$dony_bundle" >/dev/null 2>&1; then xattr -d com.apple.FinderInfo "$dony_bundle"; fi
if [[ -f "$dony_bundle/"$'Icon\r' ]]; then rm -f "$dony_bundle/"$'Icon\r'; fi
codesign --force --deep --sign - "$dony_bundle"
codesign --verify --deep --strict "$dony_bundle"
print -r -- "Built: $dony_bundle"
