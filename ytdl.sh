#!/bin/bash
#
# ytdl - Advanced YouTube-DL wrapper script
# Version: 1.0.0
#
# Description: Interactive downloader for YouTube videos and playlists
#             with support for parallel downloads and format selection.
#
# Author: RAI SULEMAN
# License: MIT
#
# Dependencies: yt-dlp, aria2c, jq, tput
#
# Usage: ./ytdl
#        Follow the interactive prompts to select download mode and options.


# ... color and header definitions ...
# Colors
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

# Editor configuration
EDITOR="${EDITOR:-nano}"  # Default to nano if not set

# Initialize global variables
SAVE_DIR=${SAVE_DIR:-"$HOME/Downloads"}

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${RESET}"
    # Kill any running background processes
    jobs -p | xargs -r kill >/dev/null 2>&1
    # Remove temporary files
    [ -f "$SAVE_DIR/video_urls.txt" ] && rm -f "$SAVE_DIR/video_urls.txt"
    rm -f ./*.download_status 2>/dev/null
    rm -rf "$TEMP_DIR" 2>/dev/null
    # Reset variables
    AUDIO_ONLY=""
    POST_PROCESS=""
    FORMAT_SORT=""
    FORMAT=""
    exit "${1:-0}"
}

# Set up traps
trap 'cleanup 1' SIGINT SIGTERM
trap 'cleanup' EXIT

# === Function definitions ===

# Print section header
header() {
    echo -e "\n${CYAN}========== $1 ==========${RESET}"
}

# Error handling function with more useful information
error_exit() {
    local msg="$1"
    local code="${2:-1}"
    echo -e "\n${RED}Error: ${msg}${RESET}" >&2
    echo -e "${YELLOW}If this error persists, try:${RESET}"
    echo "1. Check your internet connection"
    echo "2. Verify the URL is accessible in a browser"
    echo "3. Make sure yt-dlp is up to date"
    exit "$code"
}

# Check Internet Connectivity
check_internet() {
    ping -q -c 1 -W 1 8.8.8.8 >/dev/null 2>&1
}

# Validate URL format
validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

# Preprocess URL to remove problematic parameters
preprocess_url() {
    local url="$1"
    # Remove any extra parameters that might cause issues
    url=$(echo "$url" | sed 's/&feature=share//g')
    echo "$url"
}

# Show download progress for sequential downloads
show_download_progress() {
    local current="$1"
    local total="$2"
    echo -e "\n${CYAN}Progress: [$current/$total]${RESET}"
}

# Optimized monitor function for parallel downloads
monitor_downloads() {
    local temp_dir="$1"
    local total_files=${#VIDEO_URLS[@]}
    local start_time=$(date +%s)
    local status_files=()
    
    # Pre-populate status files array for efficiency
    mapfile -t status_files < <(find "$temp_dir" -name "*.status" -type f)
    
    while [[ $total_files -gt 0 ]]; do
        local completed=0 success=0 failed=0
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Re-check files every 5 iterations for newly created files
        if (( $(( $(date +%s) % 5 )) == 0 )); then
            mapfile -t status_files < <(find "$temp_dir" -name "*.status" -type f)
        fi
        
        for file in "${status_files[@]}"; do
            [[ -f "$file" ]] || continue
            case $(cat "$file") in
                "success") ((success++)); ((completed++));;
                "failed") ((failed++)); ((completed++));;
            esac
        done
        
        # Calculate percentage
        local percent=0
        [[ $total_files -gt 0 && $completed -gt 0 ]] && percent=$((completed * 100 / total_files))
        
        printf "\rProgress: %d/%d [%d%% done] (Success: %d, Failed: %d, Time: %02d:%02d)" \
               "$completed" "$total_files" \
               "$percent" \
               "$success" "$failed" \
               $((elapsed / 60)) $((elapsed % 60))
        
        [[ $completed -eq $total_files ]] && break
        sleep 1
    done
    echo
}


# Pre-define common command arguments for efficiency
declare -a BASE_ARGS=(
    --restrict-filenames
    --external-downloader aria2c
    --external-downloader-args "aria2c:-x 16 -k 1M --summary-interval=0"
    --retries 10
    --fragment-retries 10
    --no-overwrites
    --no-abort-on-error
    --ignore-errors
    --continue
    --embed-thumbnail
    --embed-metadata
    --no-write-thumbnail
    --no-write-info-json
    --no-simulate
    --progress
    --console-title
    --yes-playlist
)

# Quality selection (user enters a format code or uses presets)

select_quality() {
    header "Choose a quality option"
    echo -e "${GREEN}1) Video (144p)\n2) Video (240p)\n3) Video (360p)\n4) Video (480p)\n5) Video (720p)\n6) Video (1080p)\n7) Video (1440p)\n8) Video (2160p)\n9) Best available video"
    echo -e "${GREEN}10) Audio (mp3)\n11) Audio (aac)\n12) Audio (opus)\n13) Audio (best quality)\n14) Audio (best available bitrate)${RESET}"
    read -rp "Enter choice [1-14]: " QUALITY_CHOICE

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
        # Audio formats with fallbacks
        10) FORMAT="bestaudio/best" && AUDIO_ONLY=1 && POST_PROCESS="-x --audio-format mp3";;    # Audio MP3
        11) FORMAT="bestaudio/best" && AUDIO_ONLY=1 && POST_PROCESS="-x --audio-format aac";;    # Audio AAC
        12) FORMAT="bestaudio/best" && AUDIO_ONLY=1 && POST_PROCESS="-x --audio-format opus";;   # Audio Opus
        13) FORMAT="bestaudio/best" && AUDIO_ONLY=1 && POST_PROCESS="-x";;                       # Best audio quality
        14) FORMAT="bestaudio/best" && AUDIO_ONLY=1 && POST_PROCESS="-x";;                       # Best audio by bitrate
        *) echo "${RED}Invalid selection. Exiting.${RESET}"; exit 1;;
    esac
}


# Format validation and fallback with optimization
validate_format() {
    local url="$1"
    
    # Skip validation for audio-only formats
    if [[ -n "$AUDIO_ONLY" && "$AUDIO_ONLY" -eq 1 ]]; then
        return 0
    fi
    
    # Quick format check without downloading
    if ! yt-dlp -F "$url" --no-playlist --quiet &>/dev/null; then
        echo -e "${YELLOW}Cannot retrieve format list. Using best quality.${RESET}"
        FORMAT="bestvideo+bestaudio/best"
        return 0
    fi
    
    # For video formats, validate selected format
    if ! yt-dlp -f "$FORMAT" --no-playlist --quiet --skip-download "$url" &>/dev/null; then
        echo -e "${YELLOW}Selected format unavailable. Using best quality.${RESET}"
        FORMAT="bestvideo+bestaudio/best"
    fi
    
    # Add format optimizations
    [[ "$FORMAT" == *"bestvideo"* ]] && FORMAT_SORT="--format-sort vcodec:h264"
}


# Detect Video Title

regular_download_flow() {
    local URL="$1"
    
    # Validate and preprocess URL
    if ! validate_url "$URL"; then
        error_exit "Invalid URL format: $URL. Must start with http:// or https://"
    fi
    
    # Preprocess URL to remove problematic parameters
    URL=$(preprocess_url "$URL")
    
    # Title detection
    header "Detecting Video Title"

    if [[ "$URL" == *"list="* ]]; then
    echo -e "${CYAN}Playlist Detected.${RESET}"

    PLAYLIST_JSON=$(yt-dlp --flat-playlist --dump-single-json "$URL" 2>/dev/null)
    PLAYLIST_TITLE=$(echo "$PLAYLIST_JSON" | jq -r '.title // empty')
    VIDEO_COUNT=$(echo "$PLAYLIST_JSON" | jq '.entries | length')

    echo -e "Playlist Name: ${GREEN}${PLAYLIST_TITLE:-N/A}${RESET}"
    echo -e "Video Count: ${GREEN}${VIDEO_COUNT}${RESET}"
else
    echo -e "${CYAN}Single Video Detected.${RESET}"
    VIDEO_TITLE=$(yt-dlp --get-title "$URL" 2>/dev/null)
    echo -e "Video Title: ${GREEN}${VIDEO_TITLE:-N/A}${RESET}"
fi

# Detect if input is a video with playlist or full playlist
if [[ "$URL" == *"list="* && "$URL" == *"watch?"* ]]; then
    echo -e "${YELLOW}This is a video inside a playlist.${RESET}"
    read -rp "Do you want to download (1) just this video or (2) the full playlist? " PL_CHOICE
    if [[ "$PL_CHOICE" == "1" ]]; then
        # Extract just the video ID
        VIDEO_ID=$(echo "$URL" | grep -o 'v=[^&]*' | cut -d= -f2)
        URL="https://www.youtube.com/watch?v=$VIDEO_ID"
    elif [[ "$PL_CHOICE" == "2" ]]; then
        # Extract playlist ID
        LIST_ID=$(echo "$URL" | grep -o 'list=[^&]*')
        URL="https://www.youtube.com/playlist?$LIST_ID"
    else
        echo -e "${RED}Invalid selection. Exiting.${RESET}"
        exit 1
    fi
fi

# If it's a playlist URL (after handling above), show brief info
if [[ "$URL" == *"playlist?"* ]]; then
    header "Playlist Detected"
    echo -e "${CYAN}Fetching playlist info...${RESET}"
    VIDEO_COUNT=$(yt-dlp --flat-playlist --dump-single-json "$URL" 2>/dev/null | jq '.entries | length')
    echo -e "${YELLOW}This playlist has $VIDEO_COUNT videos.${RESET}"
    echo -e "${CYAN}Playlist video titles:${RESET}"
    yt-dlp --flat-playlist --skip-download --print title "$URL"
fi

}


# Final command

download_video() {
    local VIDEO_URL="$1"

    header "Downloading..."
    header "Starting download..."

    # Validate and preprocess URL
    if ! validate_url "$VIDEO_URL"; then
        error_exit "Invalid URL format: $VIDEO_URL"
    fi
    
    # Preprocess URL to remove problematic parameters
    VIDEO_URL=$(preprocess_url "$VIDEO_URL")

    while true; do
        if check_internet; then
            # First validate the format
            validate_format "$VIDEO_URL"
            
            # Start with essential args and add from BASE_ARGS
            local cmd_args=(
                -f "$FORMAT"
                --output "$SAVE_DIR/%(title).100s.%(ext)s"
                "${BASE_ARGS[@]}"
            )

            # Add format sorting if applicable
            [[ -n "$FORMAT_SORT" ]] && cmd_args+=($FORMAT_SORT)
            
            # Add post-processing for audio if needed
            [[ -n "$POST_PROCESS" ]] && cmd_args+=($POST_PROCESS)
            
            # Add URL
            cmd_args+=("$VIDEO_URL")

            # Execute the download
            yt-dlp "${cmd_args[@]}"
            local download_result=$?
            
            # Log verbose info on failure
            if [ $download_result -ne 0 ]; then
                echo -e "${YELLOW}Download failed with exit code $download_result${RESET}"
            fi
            
            return $download_result
        else
            echo -e "${RED}No internet connection. Retrying in 10 seconds...${RESET}"
            sleep 10
        fi
    done
}


# === Interactive logic starts here ===
# === Ask user for download mode ===
echo -e "${YELLOW}========== Download Mode ==========${RESET}"
echo -e "${GREEN}1) Sequential Download${RESET} - Audio/Video Files -- Sequentially (One after the Other)"
echo -e "${GREEN}2) Parallel   Download${RESET} - Audio/Video Files in Parallel --- (All at Once)"
echo -e "${GREEN}3) Regular    Download${RESET} - Audio/Video File -or Playlist --- (Single)"
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


# First set up the download directory for all modes
echo -e "${YELLOW}Setting up download directory...${RESET}"
read -ep "${YELLOW}Enter download directory (default: ~/Downloads):${RESET} " input_dir
SAVE_DIR=${input_dir:-"$HOME/Downloads"}
mkdir -p "$SAVE_DIR" || { echo "${RED}Failed to create directory: $SAVE_DIR${RESET}"; exit 1; }

# Get URLs based on mode
if [[ "$MODE" == "sequential" || "$MODE" == "parallel" ]]; then
    echo -e "${CYAN}Please enter one video URL per line.${RESET}"
    echo -e "${YELLOW}Your default editor will open. Save and close it when done.${RESET}"
    $EDITOR "$SAVE_DIR/video_urls.txt"
    
    # Check if the file exists and is not empty
    if [ ! -s "$SAVE_DIR/video_urls.txt" ]; then
        error_exit "No URLs provided or file empty"
    fi
    
    # Load URLs and validate them
    mapfile -t VIDEO_URLS < "$SAVE_DIR/video_urls.txt"
    
    # Validate we have URLs
    if [ ${#VIDEO_URLS[@]} -eq 0 ]; then
        error_exit "No URLs provided. Exiting."
    fi
    
    # Validate each URL
    for url in "${VIDEO_URLS[@]}"; do
        if ! validate_url "$url"; then
            error_exit "Invalid URL format: $url. Must start with http:// or https://"
        fi
    done
elif [[ "$MODE" == "single" ]]; then
    read -rp "${YELLOW}Enter video or playlist URL:${RESET} " VIDEO_URL
    
    # Validate URL
    if ! validate_url "$VIDEO_URL"; then
        error_exit "Invalid URL format: $VIDEO_URL. Must start with http:// or https://"
    fi
    
    # Preprocess URL
    VIDEO_URL=$(preprocess_url "$VIDEO_URL")
fi


# Central Logic Based on the Selected Mode
if [[ "$MODE" == "sequential" ]]; then
    echo -e "${CYAN}Video Titles:${RESET}"
    for URL in "${VIDEO_URLS[@]}"; do
        yt-dlp --get-title "$URL"
    done
    
    echo -e "${YELLOW}Continuing with sequential download.${RESET}"
    select_quality
    
    # Confirm before proceeding
    read -rp "Proceed with download? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }
    
    # Initialize download tracking variables outside of for loop
    declare -i total current success failed
    total=${#VIDEO_URLS[@]}
    current=0
    success=0
    failed=0
    local start_time=$(date +%s)
    
    # Save post-processing for sequential downloads
    SAVE_POST_PROCESS="$POST_PROCESS"
    SAVE_FORMAT_SORT="$FORMAT_SORT"
    
    for URL in "${VIDEO_URLS[@]}"; do
        ((current++))
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        echo -e "\n${CYAN}Progress: [$current/$total] - $((current * 100 / total))% done (Time: $(printf "%02d:%02d" $((elapsed / 60)) $((elapsed % 60))))${RESET}"
        
        # Restore post-processing for this URL
        POST_PROCESS="$SAVE_POST_PROCESS"
        FORMAT_SORT="$SAVE_FORMAT_SORT"
        
        if download_video "$URL"; then
            ((success++))
        else
            ((failed++))
            echo -e "${RED}Failed to download: $URL${RESET}"
        fi
    done

    # Show final status
    if [ $failed -eq 0 ]; then
        echo -e "\n${GREEN}✅ All downloads completed successfully!${RESET}"
        echo -e "${CYAN}Saved to:${RESET} $SAVE_DIR"
    else
        echo -e "\n${RED}❌ Some downloads failed ($failed of $total failed)${RESET}"
        echo -e "${CYAN}Saved successful downloads to:${RESET} $SAVE_DIR"
        exit 1
    fi
elif [[ "$MODE" == "parallel" ]]; then
    echo -e "${CYAN}Video Titles:${RESET}"
    for URL in "${VIDEO_URLS[@]}"; do
        yt-dlp --get-title "$URL"
    done
    
    echo -e "${YELLOW}Continuing with parallel download.${RESET}"
    select_quality
    
    # Confirm before proceeding
    read -rp "Proceed with download? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }
    
    # Save post-processing for parallel downloads
    SAVE_POST_PROCESS="$POST_PROCESS"
    
    # Create status tracking directory
    TEMP_DIR=$(mktemp -d)
    
    # Start downloads with status tracking
    for URL in "${VIDEO_URLS[@]}"; do
        (
            # Get video title for status
            TITLE=$(yt-dlp --get-title "$URL" 2>/dev/null || echo "$URL")
            STATUS_FILE="${TEMP_DIR}/$(echo "$URL" | md5sum | cut -d' ' -f1).status"
            echo "pending" > "$STATUS_FILE"
            
            # Restore post-processing for this URL
            POST_PROCESS="$SAVE_POST_PROCESS"
            
            if download_video "$URL"; then
                echo "success" > "$STATUS_FILE"
            else
                echo "failed" > "$STATUS_FILE"
            fi
        ) &
    done

    # Monitor progress using the dedicated function
    monitor_downloads "$TEMP_DIR"

    # Final status check
    failed_count=$(grep -l "failed" "$TEMP_DIR"/*.status 2>/dev/null | wc -l || echo "0")
    if [ "$failed_count" -eq 0 ]; then
        echo -e "\n${GREEN}✅ All downloads completed successfully!${RESET}"
        echo -e "${CYAN}Saved to:${RESET} $SAVE_DIR"
    else
        echo -e "\n${RED}❌ Some downloads failed ($failed_count failed)${RESET}"
        echo -e "${CYAN}Saved successful downloads to:${RESET} $SAVE_DIR"
        exit 1
    fi
    
    # Cleanup handled by trap
elif [[ "$MODE" == "single" ]]; then
    regular_download_flow "$VIDEO_URL"
    select_quality
    
    # Validate format
    validate_format "$VIDEO_URL"
    
    # Confirm before proceeding
    read -rp "Proceed with download? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborting."; exit 1; }
    
    # Download video
    download_video "$VIDEO_URL"
    
    # Reset for next run
    AUDIO_ONLY=""
    POST_PROCESS=""
    
    download_status=$?
    # Check status for single mode
    if [ $download_status -eq 0 ]; then
        echo -e "\n${GREEN}✅ Download completed successfully!${RESET}"
        echo -e "${CYAN}Saved to:${RESET} $SAVE_DIR"
    else
        echo -e "\n${RED}❌ Download failed (exit code: $download_status).${RESET}"
        echo -e "${CYAN}Check your URL or internet connection.${RESET}"
    fi
fi

