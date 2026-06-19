#!/usr/bin/env bash
# Builds, signs (Developer ID), notarizes, and staples a distributable Quiz Editor.app.
#
# Usage:
#   Scripts/release.sh <version> [notary-profile]
#
# Prerequisites:
#   - A "Developer ID Application" certificate in the login keychain.
#   - A notarytool keychain profile (default name: QuizEditorNotary). Create once:
#       xcrun notarytool store-credentials QuizEditorNotary \
#         --apple-id "<your-apple-id>" --team-id C25Q3Q4YFN --password "<app-specific-password>"
#     (Or use --key/--key-id/--issuer for an App Store Connect API key.)
#
# If the notary profile is missing, the script still produces a SIGNED (un-notarized)
# .app and zip, then prints the command to finish notarization.
set -euo pipefail

VERSION="${1:-0.1.0}"
NOTARY_PROFILE="${2:-QuizEditorNotary}"
BUNDLE_ID="com.byronroush.quizeditor"
SIGN_ID="Developer ID Application: BYRON ROBERT ROUSH (C25Q3Q4YFN)"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Quiz Editor.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "▸ Building release binary…"
swift build -c release --product QuizEditorApp
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "▸ Assembling app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_DIR/QuizEditorApp" "$MACOS_DIR/QuizEditorApp"
chmod +x "$MACOS_DIR/QuizEditorApp"
[[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]] && cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>QuizEditorApp</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Quiz Editor</string>
    <key>CFBundleDisplayName</key><string>Quiz Editor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Byron R Roush. MIT License.</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array><dict>
        <key>CFBundleTypeName</key><string>Quiz Editor Document</string>
        <key>CFBundleTypeRole</key><string>Editor</string>
        <key>LSHandlerRank</key><string>Owner</string>
        <key>LSItemContentTypes</key><array><string>com.byronroush.quizeditor.quiz</string></array>
    </dict></array>
    <key>UTExportedTypeDeclarations</key>
    <array><dict>
        <key>UTTypeIdentifier</key><string>com.byronroush.quizeditor.quiz</string>
        <key>UTTypeDescription</key><string>Quiz Editor Document</string>
        <key>UTTypeConformsTo</key><array><string>public.json</string></array>
        <key>UTTypeTagSpecification</key>
        <dict><key>public.filename-extension</key><array><string>quizeditor</string></array></dict>
    </dict></array>
</dict>
</plist>
PLIST

echo "▸ Code signing with hardened runtime…"
codesign --force --options runtime --timestamp \
    --sign "$SIGN_ID" "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

ZIP_PATH="$DIST_DIR/QuizEditor-$VERSION.zip"
echo "▸ Zipping for notarization…"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "▸ Submitting to Apple notary service (profile: $NOTARY_PROFILE)…"
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "▸ Stapling ticket…"
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"
    echo "▸ Re-zipping stapled app…"
    rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
    echo "✅ Notarized, stapled, and zipped: $ZIP_PATH"
else
    echo "⚠️  Notary profile '$NOTARY_PROFILE' not found — produced a SIGNED but UN-NOTARIZED build."
    echo "    Create the profile once, then re-run this script:"
    echo "      xcrun notarytool store-credentials $NOTARY_PROFILE \\"
    echo "        --apple-id \"<apple-id>\" --team-id C25Q3Q4YFN --password \"<app-specific-password>\""
    echo "    Signed zip: $ZIP_PATH"
fi
