#!/bin/bash

# Build the Swift package
swift build -c release

# Create .app bundle structure
APP_NAME="VoiceType"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp ".build/release/VoiceType" "$MACOS_DIR/"

# Copy Info.plist
cp "Sources/Info.plist" "$CONTENTS_DIR/"

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Create app icon if possible
if [ -f "Resources/AppIcon.svg" ]; then
    mkdir -p VoiceType.iconset
    
    if command -v rsvg-convert &> /dev/null; then
        for size in 16 32 128 256 512; do
            rsvg-convert -w $size -h $size Resources/AppIcon.svg > "VoiceType.iconset/icon_${size}x${size}.png"
            rsvg-convert -w $((size*2)) -h $((size*2)) Resources/AppIcon.svg > "VoiceType.iconset/icon_${size}x${size}@2x.png"
        done
        iconutil -c icns VoiceType.iconset -o "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null && echo "✅ Created app icon"
    fi
    rm -rf VoiceType.iconset
fi

echo "✅ Built $APP_DIR"
echo ""
echo "To run:"
echo "  open $APP_DIR"
echo ""
echo "Or to install:"
echo "  cp -r $APP_DIR /Applications/"
echo ""
echo "⚠️  First run requires:"
echo "  1. System Settings > Privacy & Security > Accessibility > Enable VoiceType"
echo "  2. System Settings > Privacy & Security > Microphone > Enable VoiceType"
