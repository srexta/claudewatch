#!/bin/sh
set -e
cd "$(dirname "$0")"
APP=ClaudeWatch.app
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -parse-as-library ClaudeWatch.swift -o "$APP/Contents/MacOS/ClaudeWatch"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ClaudeWatch</string>
<key>CFBundleIdentifier</key><string>local.claudewatch</string>
<key>CFBundleName</key><string>ClaudeWatch</string>
<key>LSUIElement</key><true/>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDisplayName</key><string>ClaudeWatch</string>
</dict></plist>
EOF
echo "Built $PWD/$APP"
pkill -x ClaudeWatch || true
rm -rf /Applications/ClaudeWatch.app
cp -R "$APP" /Applications/
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/ClaudeWatch.app
mdimport /Applications/ClaudeWatch.app
open /Applications/ClaudeWatch.app
echo "Installed /Applications/ClaudeWatch.app"
