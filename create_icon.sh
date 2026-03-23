#!/bin/bash

# Create iconset directory
mkdir -p VoiceType.iconset

# Check if we have the SVG and can convert
if command -v rsvg-convert &> /dev/null; then
    # Use rsvg-convert if available
    for size in 16 32 64 128 256 512; do
        rsvg-convert -w $size -h $size Resources/AppIcon.svg > "VoiceType.iconset/icon_${size}x${size}.png"
        rsvg-convert -w $((size*2)) -h $((size*2)) Resources/AppIcon.svg > "VoiceType.iconset/icon_${size}x${size}@2x.png"
    done
elif command -v sips &> /dev/null && command -v qlmanage &> /dev/null; then
    # Fallback: create a simple PNG using macOS tools
    # First create a basic PNG from the SVG using qlmanage
    qlmanage -t -s 1024 -o . Resources/AppIcon.svg 2>/dev/null
    if [ -f "AppIcon.svg.png" ]; then
        mv AppIcon.svg.png base_icon.png
        for size in 16 32 64 128 256 512; do
            sips -z $size $size base_icon.png --out "VoiceType.iconset/icon_${size}x${size}.png" 2>/dev/null
            sips -z $((size*2)) $((size*2)) base_icon.png --out "VoiceType.iconset/icon_${size}x${size}@2x.png" 2>/dev/null
        done
        rm base_icon.png
    fi
fi

# Create icns file if iconset has files
if [ "$(ls -A VoiceType.iconset 2>/dev/null)" ]; then
    iconutil -c icns VoiceType.iconset -o VoiceType.app/Contents/Resources/AppIcon.icns 2>/dev/null
    echo "✅ Created AppIcon.icns"
else
    echo "⚠️ Could not create icon images. Install librsvg: brew install librsvg"
fi

# Cleanup
rm -rf VoiceType.iconset
