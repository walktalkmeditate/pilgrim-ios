#!/bin/bash
set -euo pipefail

DEVICE="iPhone 17 Pro Max"
OUTPUT_DIR="/tmp/pilgrim-video"
VIDEO_FILE="$OUTPUT_DIR/walkthrough-raw.mp4"
SOUNDSCAPE_URL="https://cdn.pilgrimapp.org/audio/soundscape/deep-forest.aac"
SOUNDSCAPE_FILE="$OUTPUT_DIR/deep-forest.aac"

mkdir -p "$OUTPUT_DIR"

echo "=== Pilgrim App Preview Video ==="
echo ""
echo "Before running, make sure:"
echo "  1. Simulator '$DEVICE' is booted"
echo "  2. Location is set to City Run (Features > Location > City Run)"
echo "  3. VideoWalkthrough.swift is in the ScreenshotTests target"
echo ""
read -p "Press Enter to start recording..."

# Download soundscape if not cached
if [ ! -f "$SOUNDSCAPE_FILE" ]; then
    echo "Downloading Deep Forest soundscape..."
    curl -sL "$SOUNDSCAPE_URL" -o "$SOUNDSCAPE_FILE"
fi

# Get device UDID
UDID=$(xcrun simctl list devices booted -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    for d in devices:
        if d['isAvailable'] and d['state'] == 'Booted':
            print(d['udid']); sys.exit()
")

if [ -z "$UDID" ]; then
    echo "Error: No booted simulator found. Boot '$DEVICE' first."
    exit 1
fi

echo "Recording simulator: $UDID"
echo ""

# Start recording in background
xcrun simctl io "$UDID" recordVideo --codec h264 "$VIDEO_FILE" &
RECORD_PID=$!

sleep 2

# Run the video walkthrough test
echo "Running video walkthrough test..."
xcodebuild test \
    -workspace Pilgrim.xcworkspace \
    -scheme Pilgrim \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -only-testing:ScreenshotTests/VideoWalkthrough \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    -quiet 2>/dev/null || true

sleep 2

# Stop recording
kill $RECORD_PID 2>/dev/null || true
wait $RECORD_PID 2>/dev/null || true

echo ""
echo "Raw video saved: $VIDEO_FILE"
echo "Soundscape audio: $SOUNDSCAPE_FILE"
echo ""
echo "Next steps:"
echo "  1. Open $VIDEO_FILE in iMovie or Final Cut"
echo "  2. Add $SOUNDSCAPE_FILE as background audio (fade in at 3s, fade out at 27s)"
echo "  3. Add a meditation bell sound at the meditation moment (~12s)"
echo "  4. Trim to exactly 30 seconds"
echo "  5. Export at 1320x2868 (iPhone 17 Pro Max resolution)"
echo ""
echo "Files are in: $OUTPUT_DIR"
