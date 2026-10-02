#!/usr/bin/env bash
# Builds ColonEmoji.app and installs it to ~/Applications.
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/build/ColonEmoji.app"
install_dir="$HOME/Applications"

cd "$project_dir"
swift build -c release

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/ColonEmoji" "$app_dir/Contents/MacOS/ColonEmoji"
cp Resources/emoji.json "$app_dir/Contents/Resources/emoji.json"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cp THIRD_PARTY_NOTICES.md "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.md"

cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.nathaniellentz.colon-emoji</string>
    <key>CFBundleName</key><string>ColonEmoji</string>
    <key>CFBundleExecutable</key><string>ColonEmoji</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# A stable identity keeps the Accessibility grant across rebuilds; ad-hoc signatures change every build.
signing_identity="$(security find-identity -p codesigning | awk '/"ColonEmoji Local Signing"/ { print $2; exit }')"
if [[ -z "$signing_identity" ]]; then
    echo "warning: 'ColonEmoji Local Signing' not in keychain; ad-hoc signing, Accessibility must be re-granted" >&2
    signing_identity="-"
fi
codesign --force --sign "$signing_identity" "$app_dir"

mkdir -p "$project_dir/dist"
rm -f "$project_dir/dist/ColonEmoji.zip"
ditto -c -k --keepParent "$app_dir" "$project_dir/dist/ColonEmoji.zip"
echo "shareable zip: $project_dir/dist/ColonEmoji.zip"

mkdir -p "$install_dir"
pkill -x ColonEmoji || true
rm -rf "$install_dir/ColonEmoji.app"
cp -R "$app_dir" "$install_dir/ColonEmoji.app"
echo "installed $install_dir/ColonEmoji.app"
