#!/bin/bash
# This script depends on ffmpeg imagemagic and yt-dlp
# and potrace
# The purpose of this script is to partially automate 
# converting videos to lasercuttable images.
#
# Still trying to figure out how to convert units to 
# mm or inches, fill to 0, and stroke to red.
# Check if URL is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <YouTube_URL>"
    exit 1
fi

# Variables
URL="$1"
DATE=$(date +%Y-%m-%d-%H-%M)
PROJECT_DIR="./$DATE"
FRAMES_DIR="$PROJECT_DIR/frames"
SELECTED_DIR="$FRAMES_DIR/selected"
OUTPUT_DIR="$PROJECT_DIR/output"

# Create project, frames, selected, and output folders
mkdir -p "$FRAMES_DIR"
mkdir -p "$SELECTED_DIR"
mkdir -p "$OUTPUT_DIR"

# Download video using yt-dlp and wait for it to complete
echo "Downloading video..."
yt-dlp "$URL" -o "$PROJECT_DIR/video.%(ext)s" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Failed to download video."
    exit 1
fi
echo "Video downloaded."

# Find the downloaded video file (any video format)
VIDEO_FILE=$(find "$PROJECT_DIR" -type f \( -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.flv" \) | head -n 1)

# Check if video file is found
if [ -z "$VIDEO_FILE" ]; then
    echo "No video file found."
    exit 1
fi

# Process video with ffmpeg for edge detection (silenced output)
echo "Processing video with edge detection..."
ffmpeg -i "$VIDEO_FILE" -vf "scale=800:-1,edgedetect" "$PROJECT_DIR/out2.mp4" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error processing video with ffmpeg."
    exit 1
fi
echo "Video processing complete."

# Extract frames at 1 frame per second (silenced output) and place in frames folder
echo "Extracting frames..."
FRAME_COUNT=$(ffmpeg -i "$PROJECT_DIR/out2.mp4" 2>&1 | grep "Duration" | awk '{print $2}' | tr -d , | awk -F: '{print ($1 * 3600) + ($2 * 60) + $3}')
TOTAL_FRAMES=$((FRAME_COUNT)) # 1 fps
ffmpeg -i "$PROJECT_DIR/out2.mp4" -r 1 "$FRAMES_DIR/output_%04d.png" > /dev/null 2>&1 &
FFMPEG_PID=$!

# Display progress bar for frame extraction
while kill -0 $FFMPEG_PID 2> /dev/null; do
    EXTRACTED=$(ls -1q "$FRAMES_DIR"/*.png 2>/dev/null | wc -l)
    PERCENTAGE=$((EXTRACTED * 100 / TOTAL_FRAMES))
    echo -ne "Frame extraction: $EXTRACTED/$TOTAL_FRAMES ($PERCENTAGE%)\r"
    sleep 1
done
echo -e "\nFrames extraction complete."

# Notify user to review frames
echo "Review the frames in '$FRAMES_DIR' and move the ones you want to keep into '$SELECTED_DIR'."
read -p "Press Enter once you're done reviewing and moving the frames..."

# Convert PNGs in selected folder to SVG
TOTAL_FILES=$(ls -1q "$SELECTED_DIR"/*.png 2>/dev/null | wc -l)
CURRENT_FILE=0

if [ $TOTAL_FILES -gt 0 ]; then
    echo "Converting selected frames to SVG..."
    for i in "$SELECTED_DIR"/*.png; do
        if [ -f "$i" ]; then
            BASENAME=$(basename "$i" .png)
            convert "$i" -edge 2 -morphology Thinning:-2 Skeleton "$OUTPUT_DIR/$BASENAME.svg"
            
            # Modify the SVG to change fill and stroke
            sed -i 's/fill="#000000" stroke="none"/fill="#FFFFFF" stroke="red"/g' "$OUTPUT_DIR/$BASENAME.svg"
            
            # Insert or modify the SVG size units (e.g., in inches or mm)
            sed -i '/<svg / s/viewBox="/&0 0 800 600"/' "$OUTPUT_DIR/$BASENAME.svg"
            sed -i 's/<svg /<svg xmlns="http:\/\/www.w3.org\/2000\/svg" width="10in" height="8in" /' "$OUTPUT_DIR/$BASENAME.svg"

            # Update progress
            ((CURRENT_FILE++))
            echo "Processed $CURRENT_FILE of $TOTAL_FILES frames..."
        fi
    done
    echo "SVG conversion completed! Check the '$OUTPUT_DIR' directory for the results."
else
    echo "No frames found in '$SELECTED_DIR'."
fi
