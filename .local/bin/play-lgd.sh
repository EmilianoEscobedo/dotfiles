#!/bin/bash

PLAYLIST_FILE="$HOME/.local/share/music_playlist.txt"

mkdir -p "$(dirname "$PLAYLIST_FILE")"
touch "$PLAYLIST_FILE"

show_current_song() {
    echo "♪ Now playing: $1"
}

search_songs() {
    query="$1"
    echo "Searching: $query"
    echo "Loading results..."
    results=$(yt-dlp "ytsearch5:$query" -j | jq -r '[.title, .webpage_url] | @tsv')

    i=1
    while IFS=$'\t' read -r title url; do
        echo "$i) $title"
        urls[$i]=$url
        titles[$i]=$title
        ((i++))
    done <<< "$results"

    echo -e "\nSelect a number (1-5) to play, or add 'a' to add to playlist (e.g., '1' or '1a'): "
    read choice

    number=${choice//[^0-9]/}
    if [[ $number -ge 1 && $number -le 5 ]]; then
        selected_url=${urls[$number]}
        selected_title=${titles[$number]}
        echo "$selected_url" > /tmp/current_playing.txt
        
        if [[ $choice =~ "a" ]]; then
            echo "$selected_url # $selected_title" >> "$PLAYLIST_FILE"
            echo "Added to playlist: $selected_title"
        fi
        
        show_current_song "$selected_title"
        mpv --no-video "$selected_url"
    else
        echo "Invalid selection"
    fi
}

add_to_playlist() {
    if [ -f /tmp/current_playing.txt ]; then
        url=$(cat /tmp/current_playing.txt)
        title=$(yt-dlp --get-title "$url")
        echo "$url # $title" >> "$PLAYLIST_FILE"
        echo "Added to playlist: $title"
    else
        echo "Play something to add it to the playlist"
    fi
}

play_playlist() {
    if [ -s "$PLAYLIST_FILE" ]; then
        echo "Reproducing playlist..."
        playlist_urls=$(cut -d '#' -f1 "$PLAYLIST_FILE")
        mpv --playlist=<(echo "$playlist_urls")
    else
        echo "Empty playlist :("
    fi
}

show_help() {
    echo "Usage: $0 [option] [argument]"
    echo "Options:"
    echo "  -s, --search 'title'    Search and show 5 results to choose from"
    echo "  -a, --add               Add last reproduced song to playlist"
    echo "  -p, --play              Reproduce the playlist"
    echo "  -h, --help              Display this manual"
    echo ""
    echo "MPV Controls:"
    echo "  LEFT/RIGHT              Seek backward/forward"
    echo "  ,/.                     Previous/next frame (with frame-step)"
    echo "  SPACE or p             Play/Pause"
    echo "  9/0                     Decrease/increase volume"
    echo "  m                       Mute"
    echo "  [/]                     Decrease/increase playback speed"
    echo "  q                       Quit"
    echo "  >                       Next playlist entry"
    echo "  <                       Previous playlist entry"
}

case "$1" in
    -s|--search)
        if [ -n "$2" ]; then
            search_songs "$2"
        else
            echo "Error: you must provide the title of the song"
            show_help
        fi
        ;;
    -a|--add)
        add_to_playlist
        ;;
    -p|--play)
        play_playlist
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo "Not valid option"
        show_help
        ;;
esac
