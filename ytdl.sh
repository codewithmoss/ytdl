#!/bin/bash

# ytdl: Interactive yt-dlp downloader
# Requires: yt-dlp, aria2c, jq, tput
# Author: RAI SULEMAN


# ... color and header definitions ...
# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

# Function to print a header
header() {
    echo -e "\n${CYAN}========== $1 ==========${RESET}"
}


# === Function definitions go here ===



# Check Internet Connectivity
check_internet() {
    ping -q -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}


# Quality selection (user enters a format code or uses presets)

select_quality() {
header "Choose a video quality"
echo -e "${GREEN}1) 144p\n2) 240p\n3) 360p\n4) 480p\n5) 720p\n6) 1080p\n7) 1440p\n8) 2160p\n9) Best available${RESET}"
read -rp "Enter choice [1-9]: " QUALITY_CHOICE

# Map quality choice to format selector
case $QUALITY_CHOICE in
    1) FORMAT="bestvideo[height<=144]+bestaudio/best[height<=144]";;
    2) FORMAT="bestvideo[height<=240]+bestaudio/best[height<=240]";;
    3) FORMAT="bestvideo[height<=360]+bestaudio/best[height<=360]";;
    4) FORMAT="bestvideo[height<=480]+bestaudio/best[height<=480]";;
    5) FORMAT="bestvideo[height<=720]+bestaudio/best[height<=720]";;
    6) FORMAT="bestvideo[height<=1080]+bestaudio/best[height<=1080]";;
    7) FORMAT="bestvideo[height<=1440]+bestaudio/best[height<=1440]";;
    8) FORMAT="bestvideo[height<=2160]+bestaudio/best[height<=2160]";;
    9) FORMAT="bestvideo+bestaudio/best";;
    *) echo "${RED}Invalid selection. Exiting.${RESET}"; exit 1;;
esac
}


# Get save location

select_output_path() {
read -rp "${YELLOW}Enter download directory (default: ~/Downloads):${RESET} " SAVE_DIR
SAVE_DIR=${SAVE_DIR:-"$HOME/Downloads"}

mkdir -p "$SAVE_DIR" || { echo "${RED}Failed to create directory: $SAVE_DIR${RESET}"; exit 1; }
}


# Detect Video Title

regular_download_flow() {
    local URL="$1"
# Title detection
echo -e "${YELLOW}========== Detecting Video Title ==========${RESET}"

if [[ "$VIDEO_URL" == *"list="* ]]; then
    echo -e "${CYAN}Playlist Detected.${RESET}"

    PLAYLIST_JSON=$(yt-dlp --flat-playlist --dump-single-json "$VIDEO_URL" 2>/dev/null)
    PLAYLIST_TITLE=$(echo "$PLAYLIST_JSON" | jq -r '.title // empty')
    VIDEO_COUNT=$(echo "$PLAYLIST_JSON" | jq '.entries | length')

    echo -e "Playlist Name: ${GREEN}${PLAYLIST_TITLE:-N/A}${RESET}"
    echo -e "Video Count: ${GREEN}${VIDEO_COUNT}${RESET}"
else
    echo -e "${CYAN}Single Video Detected.${RESET}"
    VIDEO_TITLE=$(yt-dlp --get-title "$VIDEO_URL" 2>/dev/null)
    echo -e "Video Title: ${GREEN}${VIDEO_TITLE:-N/A}${RESET}"
fi

# Detect if input is a video with playlist or full playlist
if [[ "$VIDEO_URL" == *"list="* && "$VIDEO_URL" == *"watch?"* ]]; then
    echo -e "${YELLOW}This is a video inside a playlist.${RESET}"
    read -rp "Do you want to download (1) just this video or (2) the full playlist? " PL_CHOICE
    if [[ "$PL_CHOICE" == "1" ]]; then
        # Extract just the video ID
        VIDEO_ID=$(echo "$VIDEO_URL" | grep -o 'v=[^&]*' | cut -d= -f2)
        VIDEO_URL="https://www.youtube.com/watch?v=$VIDEO_ID"
    elif [[ "$PL_CHOICE" == "2" ]]; then
        # Extract playlist ID
        LIST_ID=$(echo "$VIDEO_URL" | grep -o 'list=[^&]*')
        VIDEO_URL="https://www.youtube.com/playlist?$LIST_ID"
    else
        echo -e "${RED}Invalid selection. Exiting.${RESET}"
        exit 1
    fi
fi

# If it's a playlist URL (after handling above), show brief info
if [[ "$VIDEO_URL" == *"playlist?"* ]]; then
    header "Playlist Detected"
    echo -e "${CYAN}Fetching playlist info...${RESET}"
    VIDEO_COUNT=$(yt-dlp --flat-playlist --dump-single-json "$VIDEO_URL" 2>/dev/null | jq '.entries | length')
    echo -e "${YELLOW}This playlist has $VIDEO_COUNT videos.${RESET}"
    echo -e "${CYAN}Playlist video titles:${RESET}"
    yt-dlp --flat-playlist --skip-download --print title "$VIDEO_URL"
fi

}


# Final command

download_video() {
    local VIDEO_URL="$1"

    header "Downloading..."
    header "Starting download..."

    while true; do
        if check_internet; then
            yt-dlp \
                -f "$FORMAT" \
                --output "$SAVE_DIR/%(title).100s.%(ext)s" --restrict-filenames \
                --external-downloader aria2c \
                --external-downloader-args "aria2c:-x 16 -k 1M --summary-interval=0" \
                --retries 10 \
                --fragment-retries 10 \
                --no-overwrites \
                --no-abort-on-error \
                --ignore-errors \
                --continue \
                --embed-thumbnail \
                --embed-metadata \
                --no-write-thumbnail \
                --no-write-info-json \
                --no-simulate --progress \
                --console-title \
                --yes-playlist \
                "$VIDEO_URL"
            break  # Exit the loop if yt-dlp finishes successfully
        else
            echo -e "${RED}No internet connection. Retrying in 10 seconds...${RESET}"
            sleep 10
        fi
    done
}


# === Interactive logic starts here ===
# === Ask user for download mode ===
echo -e "${YELLOW}========== Download Mode ==========${RESET}"
echo -e "${GREEN}1) Sequential download${RESET} - Download videos sequentially (One after the other)"
echo -e "${GREEN}2) Parallel download${RESET} - Download videos in parallel (All at once)"
echo -e "${GREEN}3) Single video/playlist (regular mode)${RESET} - Download one video or playlist interactively"
echo -e "${RED}4) Exit${RESET}"

read -rp "Choose a download mode [1-4]: " DOWNLOAD_MODE


case "$DOWNLOAD_MODE" in
    1)
        MODE="sequential"
        ;;
    2)
        MODE="parallel"
        ;;
    3)
        MODE="single"
        ;;
    4)
        echo -e "${RED}Exiting script.${RESET}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid option. Exiting.${RESET}"
        exit 1
        ;;
esac


if [[ "$MODE" == "sequential" || "$MODE" == "parallel" ]]; then
    echo -e "${CYAN}Please enter one video URL per line.${RESET}"
    echo -e "${YELLOW}Your default editor will open. Save and close it when done.${RESET}"
    $EDITOR video_urls.txt
    mapfile -t VIDEO_URLS < video_urls.txt  # Load into array
fi


# Central Logic Based on the Selected Mode
if [[ "$MODE" == "sequential" ]]; then
    echo -e "${CYAN}Video Titles:${RESET}"
    for URL in "${VIDEO_URLS[@]}"; do
        yt-dlp --get-title "$URL"
    done
    echo -e "${YELLOW}Continuing with sequential download.${RESET}"
    select_quality
    select_output_path
    for URL in "${VIDEO_URLS[@]}"; do
        download_video "$URL"
    done
    rm -f video_urls.txt
elif [[ "$MODE" == "parallel" ]]; then
    echo -e "${CYAN}Video Titles:${RESET}"
    for URL in "${VIDEO_URLS[@]}"; do
        yt-dlp --get-title "$URL"
    done
    echo -e "${YELLOW}Continuing with parallel download.${RESET}"
    select_quality
    select_output_path
    for URL in "${VIDEO_URLS[@]}"; do
        (download_video "$URL") &
    done
    wait  # Wait for all background jobs to finish
    rm -f video_urls.txt
elif [[ "$MODE" == "single" ]]; then
    read -rp "${YELLOW}Enter video or playlist URL:${RESET} " VIDEO_URL
    regular_download_flow "$VIDEO_URL"
    select_quality
    select_output_path
    download_video "$VIDEO_URL"
fi


# Check status
if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}✅ Download completed successfully!${RESET}"
    echo -e "${CYAN}Saved to:${RESET} $SAVE_DIR"
else
    echo -e "\n${RED}❌ Download failed.${RESET}"
    echo -e "${CYAN}Check your URL or internet connection.${RESET}"
fi
