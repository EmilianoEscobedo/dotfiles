#!/bin/bash
#
# play-lgd.sh — YouTube music player with a TUI interface
#
# Usage:
#   player                       → full TUI player (recommended)
#   player -s 'title'            → search via fzf; add result to queue & play
#   player -p                    → play saved playlist file (non-TUI)
#   player -l                    → browse/edit saved playlist via fzf
#   player -a                    → add currently-playing track to saved playlist
#   player -h                    → show help
#
# Requires: yt-dlp (>= 2026.07), mpv, ncat (nmap), fzf, python3, tput, node (>=22).
# YouTube fix lives in ~/.config/yt-dlp/config:
#   --cookies-from-browser firefox  --js-runtimes node
#   --extractor-args youtube:player_client=web_embedded
#
# NOTE: VU meter is cosmetic (RANDOM while mpv reports "playing").

set -uo pipefail

PLAYLIST_DIR="$HOME/.local/share/playlists"
WORKING_PLAYLIST="$PLAYLIST_DIR/Working.txt"
CURRENT_PLAYLIST=""
SCREEN="playlists"               # "playlists" | "player"
PL_CUR=0                         # cursor in playlist browser
MPV_SOCKET="/tmp/mpv-play-lgd-$$-$RANDOM.sock"
SEARCH_RESULTS=15
VU_COLS=50
BAR_LEN=44
YTDLP_FORMAT="251/250/249/140/ba"

declare -a QURL=() QTITLE=()
QIDX=-1
QCUR=-1
LAST_PLAYING=0

# ---------- terminal helpers ----------

INIT_TERM_CALLED=0
init_term() {
    INIT_TERM_CALLED=1
    tput smcup 2>/dev/null
    stty -echo -icanon 2>/dev/null
    echo -en "\e]11;#000000\a\e]10;#c8c8c8\a\e[?25l\e[2J\e[H"
}
restore_term() {
    [[ "$INIT_TERM_CALLED" == "1" ]] || return 0
    echo -en "\e[?25h\e]110\a\e]111\a\e[0m\e[2J"
    stty echo icanon 2>/dev/null
    tput rmcup 2>/dev/null
    tput sgr0 2>/dev/null
}

# ---------- mpv IPC ----------

mpv_start() {
    rm -f "$MPV_SOCKET"
    mpv --idle=yes --no-video --no-terminal --really-quiet --force-media-title="" \
        --input-ipc-server="$MPV_SOCKET" --ytdl-format="$YTDLP_FORMAT" >/dev/null 2>&1 &
    MPV_PID=$!
    for _ in {1..50}; do [[ -S "$MPV_SOCKET" ]] && return 0; sleep 0.05; done
    return 1
}

mpv_end() {
    [[ -n "${MPV_PID:-}" ]] || return 0
    if [[ -S "$MPV_SOCKET" ]]; then
        printf '{"command":["quit"]}\n' | ncat -U "$MPV_SOCKET" 2>/dev/null; sleep 0.1
    fi
    kill "${MPV_PID}" 2>/dev/null; wait "${MPV_PID}" 2>/dev/null
    rm -f "$MPV_SOCKET"
}
mpv_cmd()  { printf '%s\n' "$1" | ncat -U "$MPV_SOCKET" >/dev/null 2>&1; }

mpv_get_state() {
    local -a props=(${1//,/ })
    local p
    {
        for p in "${props[@]}"; do
            printf '{"command":["get_property","%s"]}\n' "$p"
        done
    } | ncat -U "$MPV_SOCKET" 2>/dev/null | python3 -c '
import sys, json
for ln in sys.stdin:
    ln=ln.strip()
    if not ln: continue
    try: d=json.loads(ln)
    except Exception: continue
    v=d.get("data")
    if v is None or isinstance(v,(dict,list)):
        print("")
    else:
        print(v)
'
}

# ---------- playlist management ----------

mkdir -p "$PLAYLIST_DIR"

# On first run after the multi-playlist update, migrate the old single-file
# playlist into "Working".
OLD_FILE="$HOME/.local/share/music_playlist.txt"
if [[ -f "$OLD_FILE" && ! -f "$WORKING_PLAYLIST" ]]; then
    mv "$OLD_FILE" "$WORKING_PLAYLIST" 2>/dev/null
fi
# Ensure Working always exists
touch "$WORKING_PLAYLIST"

playlist_list_names() {
    # Populate the passed array name with basenames of .txt files (sorted).
    # Uses a nameref so the caller gets the result:  playlist_list_names arr
    local -n out="$1"
    out=()
    local f
    for f in "$PLAYLIST_DIR"/*.txt; do
        [[ -f "$f" ]] || continue
        out+=("$(basename "$f" .txt)")
    done
}

playlist_track_count() {
    local name="$1"
    wc -l < "$PLAYLIST_DIR/$name.txt" 2>/dev/null || echo 0
}

playlist_load() {
    local name="$1"
    local f="$PLAYLIST_DIR/$name.txt"
    QURL=(); QTITLE=()
    QIDX=-1; QCUR=-1
    if [[ ! -f "$f" ]]; then CURRENT_PLAYLIST=""; return; fi
    CURRENT_PLAYLIST="$name"
    local url title
    while IFS='#' read -r url title; do
        url="${url// /}"; title="${title# }"
        [[ -z "$url" ]] && continue
        QURL+=("$url"); QTITLE+=("$title")
    done < "$f"
}

playlist_save() {
    local name="${1:-$CURRENT_PLAYLIST}"
    [[ -z "$name" ]] && return
    : > "$PLAYLIST_DIR/$name.txt"
    local i
    for ((i=0;i<${#QURL[@]};i++)); do
        printf '%s # %s\n' "${QURL[$i]}" "${QTITLE[$i]}" >> "$PLAYLIST_DIR/$name.txt"
    done
}

playlist_create() {
    local name="$1"
    [[ -z "$name" ]] && return 1
    touch "$PLAYLIST_DIR/$name.txt"
}

playlist_delete() {
    rm -f "$PLAYLIST_DIR/$1.txt"
}

playlist_rename() {
    local old="$1" new="$2"
    [[ -z "$old" || -z "$new" ]] && return 1
    mv "$PLAYLIST_DIR/$old.txt" "$PLAYLIST_DIR/$new.txt" 2>/dev/null
}

# ---------- queue ----------

queue_play_idx() {
    local i="$1"
    (( i >= 0 && i < ${#QURL[@]} )) || return 1
    QIDX="$i"; QCUR="$i"
    local title="${QTITLE[$i]}"
    echo "${QURL[$i]}" > /tmp/current_playing.txt
    mpv_cmd "{\"command\":[\"loadfile\",\"${QURL[$i]}\",\"replace\"]}"
    mpv_cmd '{"command":["set_property","force-media-title","'"$title"'"]}'
    mpv_cmd '{"command":["set_property","pause",false]}'
}
queue_next() {
    (( ${#QURL[@]} == 0 )) && return 1
    local n=$(( QIDX + 1 ))
    (( n < ${#QURL[@]} )) && { queue_play_idx "$n"; return 0; }
    return 1
}
queue_prev() {
    (( ${#QURL[@]} == 0 )) && return 1
    local p=$(( QIDX - 1 ))
    (( p >= 0 )) && { queue_play_idx "$p"; return 0; }
    return 1
}
queue_remove_at() {
    local i="$1"
    (( i >= 0 && i < ${#QURL[@]} )) || return 1
    unset 'QURL[i]'; unset 'QTITLE[i]'
    QURL=("${QURL[@]}"); QTITLE=("${QTITLE[@]}")
    if (( QIDX > i )); then QIDX=$((QIDX-1)); fi
    if (( QIDX >= ${#QURL[@]} )); then QIDX=$(( ${#QURL[@]} - 1 )); fi
    if (( QCUR > i )); then QCUR=$((QCUR-1)); fi
    if (( QCUR < 0 || QCUR >= ${#QURL[@]} )); then QCUR="$QIDX"; fi
}
queue_cursor_up() {
    (( ${#QURL[@]} == 0 )) && return 1
    (( QCUR < 0 )) && QCUR="${QIDX:-0}"
    (( QCUR > 0 )) && QCUR=$((QCUR-1)) || QCUR=0
}
queue_cursor_down() {
    (( ${#QURL[@]} == 0 )) && return 1
    (( QCUR < 0 )) && QCUR="${QIDX:-0}"
    (( QCUR < ${#QURL[@]}-1 )) && QCUR=$((QCUR+1)) || QCUR=$(( ${#QURL[@]}-1 ))
}

# ---------- search via fzf ----------

do_search() {
    local query="$1" i=0 title url
    local -a t=() u=()
    local US=$'\x1f'
    while IFS="$US" read -r title url; do
        [[ -z "$url" ]] && continue
        ((i++)); t+=("$title"); u+=("$url")
        printf '%d\t%s\n' "$i" "$title"
    done < <(yt-dlp "ytsearch${SEARCH_RESULTS}:$query" \
                    --flat-playlist --no-warnings --no-playlist \
                    --print "%(title)s${US}%(url)s" 2>/dev/null)
    (( ${#t[@]} == 0 )) && { echo "No results." >&2; sleep 1; return 1; }

    local menu="" j
    for ((j=0;j<${#t[@]};j++)); do menu+="$((j+1))"$'\t'"${t[$j]}"$'\n'; done

    local pick key
    pick=$(printf '%b' "$menu" | fzf --delimiter=$'\t' --with-nth=2.. \
        --header="Enter=queue & play  Ctrl-A=queue (multi)  Esc=cancel" \
        --expect=enter,ctrl-a --multi --height=~50% --reverse --no-info \
        --prompt="Search '$query' ▶ " 2>/dev/tty)
    [[ -z "$pick" ]] && return 130
    key=$(head -1 <<<"$pick")

    local first=true
    while IFS=$'\t' read -r idx title; do
        [[ "$idx" =~ ^[0-9]+$ ]] || continue
        local url="${u[$((idx-1))]}"
        QURL+=("$url"); QTITLE+=("$title")
        if $first && [[ "$key" == "enter" ]]; then
            queue_play_idx $(( ${#QURL[@]} - 1 ))
            first=false
        fi
    done < <(tail -n +2 <<<"$pick")
}

# ---------- save to playlist (multi-playlist) ----------

save_current_to_playlist() {
    local url="${QURL[$QIDX]:-}" title="${QTITLE[$QIDX]:-}"
    [[ -z "$url" ]] && { echo "Nothing playing." >&2; sleep 1; return; }

    if [[ -n "$CURRENT_PLAYLIST" ]]; then
        echo "$url # $title" >> "$PLAYLIST_DIR/$CURRENT_PLAYLIST.txt"
        echo "Saved to \"$CURRENT_PLAYLIST\"." >&2; sleep 1
        return
    fi

    # No current playlist: prompt user to pick one or create new
    local -a names=()
    playlist_list_names names
    local menu=""
    local j
    for ((j=0;j<${#names[@]};j++)); do
        local cnt
        cnt=$(playlist_track_count "${names[$j]}")
        menu+="$((j+1))"$'\t'"${names[$j]}  ($cnt tracks)"$'\n'
    done
    menu+="$(( ${#names[@]}+1 ))"$'\t[Create new playlist...]'$'\n'

    local pick
    pick=$(printf '%b' "$menu" | fzf --delimiter=$'\t' --with-nth=2.. \
        --header="Save to playlist (Esc=cancel)" --height=~40% --reverse \
        --prompt="Save ▶ " 2>/dev/tty)
    [[ -z "$pick" ]] && return

    local idx
    idx=$(head -1 <<<"$pick" | cut -f1)
    [[ ! "$idx" =~ ^[0-9]+$ ]] && return
    idx=$((idx - 1))

    if (( idx < ${#names[@]} )); then
        echo "$url # $title" >> "$PLAYLIST_DIR/${names[$idx]}.txt"
        CURRENT_PLAYLIST="${names[$idx]}"
        echo "Saved to \"${names[$idx]}\"." >&2; sleep 1
    else
        stty echo -icanon 2>/dev/null
        tput cup "$(tput lines 2>/dev/null || echo 24)" 0 2>/dev/null
        local new_name=""
        read_line "New playlist name: " new_name
        stty -echo -icanon 2>/dev/null
        [[ -z "$new_name" ]] && return
        touch "$PLAYLIST_DIR/$new_name.txt"
        echo "$url # $title" >> "$PLAYLIST_DIR/$new_name.txt"
        CURRENT_PLAYLIST="$new_name"
        echo "Created and saved to \"$new_name\"." >&2; sleep 1
    fi
}

# ---------- saved playlist editing (legacy, fzf-based) ----------

edit_saved_playlist() {
    local f="$PLAYLIST_DIR/${CURRENT_PLAYLIST:-Working}.txt"
    [[ -s "$f" ]] || { echo "Empty playlist." >&2; sleep 1; return; }
    local pick lno raw first_url first_title
    pick=$(awk -F' #' '{print NR"\t"$2}' "$f" | \
        fzf --delimiter=$'\t' --with-nth=2.. \
        --header="Enter=queue & play  Ctrl-D=delete  Esc=back" \
        --expect=ctrl-d,enter --multi --height=~50% --reverse 2>/dev/tty)
    [[ -z "$pick" ]] && return
    local key; key=$(head -1 <<<"$pick")
    case "$key" in
        ctrl-d)
            local -a del=()
            while IFS=$'\t' read -r lno rest; do [[ "$lno" =~ ^[0-9]+$ ]] && del+=("$lno"); done < <(tail -n +2 <<<"$pick")
            (( ${#del[@]} )) || return
            printf '%s\n' "${del[@]}" | sort -rn | while read -r l; do sed -i "${l}d" "$f"; done
            ;;
        enter)
            first=$(tail -n +2 <<<"$pick" | head -1); lno=${first%%$'\t'*}
            raw=$(sed -n "${lno}p" "$f")
            first_url=${raw%% # *}; first_url=${first_url// /}
            first_title=${raw#* # }; first_title=${first_title# }
            QURL+=("$first_url"); QTITLE+=("$first_title")
            queue_play_idx $(( ${#QURL[@]} - 1 ))
            ;;
    esac
}

# ---------- formatting helpers ----------

# ---------- input helper (Esc to cancel) ----------

# Reads a line of input one character at a time.  Esc at any point clears the
# buffer and returns empty (cancel).  Enter submits.  Backspace erases.
read_line() {
    local prompt="$1" var="$2" buf="" c
    echo -n "$prompt"
    while true; do
        read -rsN 1 c || { buf=""; break; }
        if [[ "$c" == $'\n' || "$c" == $'\r' ]]; then
            break
        elif [[ "$c" == $'\e' ]]; then
            buf=""; break
        elif [[ "$c" == $'\x7f' || "$c" == $'\b' ]]; then
            if [[ ${#buf} -gt 0 ]]; then
                buf="${buf:0:-1}"
                echo -en "\b \b"
            fi
        else
            buf+="$c"
            echo -n "$c"
        fi
    done
    printf -v "$var" '%s' "$buf"
}

format_time() {
    local s="${1:-0}"
    s=${s%.*}
    [[ -z "$s" || ! "$s" =~ ^[0-9-]+$ ]] && s=0
    (( s < 0 )) && s=0
    local h=$(( s/3600 )) m=$(( (s%3600)/60 )) sec=$(( s%60 ))
    if (( h>0 )); then printf '%d:%02d:%02d' "$h" "$m" "$sec"
    else printf '%02d:%02d' "$m" "$sec"; fi
}
progress_bar() {
    local cur="${1:-0}" total="${2:-1}"
    cur=${cur%.*}; total=${total%.*}
    [[ -z "$cur"   || ! "$cur"   =~ ^[0-9-]+$ ]] && cur=0
    [[ -z "$total" || ! "$total" =~ ^[0-9-]+$ || "$total" -eq 0 ]] && total=1
    (( cur < 0 )) && cur=0
    local pos=$(( BAR_LEN * cur / total ))
    (( pos >= BAR_LEN )) && pos=$((BAR_LEN-1))
    (( pos < 0 )) && pos=0
    local out="" i
    for ((i=0;i<BAR_LEN;i++)); do
        if (( i == pos )); then out+="●"
        elif (( i < pos )); then out+="▰"
        else out+="▱"; fi
    done
    printf '%s' "$out"
}
volume_bar() {
    local v="${1:-0}" i filled
    v=${v%.*}
    [[ -z "$v" || ! "$v" =~ ^[0-9-]+$ ]] && v=0
    (( v < 0 )) && v=0; (( v > 100 )) && v=100
    filled=$(( (BAR_LEN * v + 50) / 100 ))
    (( filled > BAR_LEN )) && filled=$BAR_LEN; (( filled < 0 )) && filled=0
    local out=""
    for ((i=0;i<BAR_LEN;i++)); do (( i < filled )) && out+="▓" || out+="░"; done
    printf '%s' "$out"
}
vu_meter() {
    local playing="$1" out="" i h
    local bars=(' ' '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█')
    if [[ "$playing" == "1" ]]; then
        for ((i=0;i<VU_COLS;i++)); do h=$(( RANDOM % 9 )); out+="${bars[$h]}"; done
    else
        for ((i=0;i<VU_COLS;i++)); do out+='░'; done
    fi
    printf '%s' "$out"
}

# ---------- player screen ----------

draw_player() {
    local R=$'\e[0m' B=$'\e[1m' DIM=$'\e[2m' CYAN=$'\e[1;36m' GREEN=$'\e[1;32m'
    local YELLOW=$'\e[1;33m' MAGENTA=$'\e[1;35m' GREY=$'\e[1;90m' RED=$'\e[1;31m'
    local YELNOTE=$'\e[3;33m'
    local EL=$'\e[K' ED=$'\e[J' HOME=$'\e[H'

    local raw
    raw=$(mpv_get_state "time-pos,duration,pause,core-idle,idle-active,volume,mute,media-title,path")
    local time_pos dur pause core_idle idle vol mute title path
    { read -r time_pos; read -r dur; read -r pause; read -r core_idle; read -r idle;
      read -r vol; read -r mute; read -r title; read -r path; } <<< "$raw"
    : "${time_pos:=0}"; : "${dur:=0}"; : "${vol:=100}"
    : "${pause:=False}"; : "${core_idle:=True}"; : "${idle:=True}"; : "${path:=}"

    local playing=0 status loaded=0
    [[ -n "$path" && "$path" != "None" ]] && loaded=1
    if [[ "$loaded" == "0" ]]; then
        status="${GREY}■ IDLE${R}"
    elif [[ "$pause" == "True" || "$pause" == "true" ]]; then
        status="${YELLOW}⏸ PAUSED${R}"
    elif [[ "$core_idle" == "True" || "$core_idle" == "true" ]]; then
        status="${MAGENTA}⟳ BUFFERING${R}"
    else
        playing=1; status="${GREEN}▶ PLAYING${R}"
    fi
    if [[ "$LAST_PLAYING" == "1" && "$loaded" == "0" ]]; then
        queue_next || true; LAST_PLAYING=0
    elif [[ "$playing" == "1" ]]; then
        LAST_PLAYING=1
    fi

    local display_title=""
    (( QIDX >= 0 && QIDX < ${#QTITLE[@]} )) && display_title="${QTITLE[$QIDX]}"
    [[ -z "$display_title" ]] && display_title="$title"
    [[ -z "$display_title" || "$display_title" == "None" ]] && display_title="(nothing loaded)"

    local cols; cols=$(tput cols 2>/dev/null || echo 80)
    local W=$cols; (( W < 60 )) && W=60
    local border; border=$(printf '━%.0s' $(seq 1 "$W"))

    echo -en "\e[?25l$HOME"

    printf '%s%s%s\n'     "$CYAN" "$border" "$R$EL"
    if [[ -n "$CURRENT_PLAYLIST" ]]; then
        printf '   %sLaingard Music Player%s [%s%s%s]\n' \
            "$B" "$R" "$CYAN" "$CURRENT_PLAYLIST" "$R$EL"
    else
        printf '   %sLaingard Music Player%s\n' \
            "$B" "$R$EL"
    fi
    printf '%s%s%s\n'     "$CYAN" "$border" "$R$EL"

    printf '%s\n' "$EL"
    local padded="${display_title:0:$((W-20))}"
    printf '   %s♪ Now playing:%s %s%s%s\n' "$YELNOTE" "$R" "$B" "$padded" "$R$EL"
    printf '%s\n' "$EL"

    # progress + status on same line
    local tpb; tpb=$(progress_bar "$time_pos" "$dur")
    printf '   %s  %s  %s  %s\n' \
        "$(format_time "$time_pos")" "$tpb" "$(format_time "$dur")" "$status$EL"
    printf '%s\n' "$EL"

    # VU
    local vub; vub=$(vu_meter "$playing")
    printf '   %s\n' "$vub$EL"
    printf '%s\n' "$EL"

    # volume
    local vb; vb=$(volume_bar "$vol")
    local mutelabel=""
    [[ "$mute" == "True" || "$mute" == "true" ]] && mutelabel=" ${RED}[MUTED]${R}"
    printf '   VOL %s %3d%%%s\n' "$vb" "${vol%.*}" "$mutelabel$EL"
    printf '%s\n' "$EL"

    # Queue
    local n=${#QURL[@]}
    if (( n == 0 )); then
        printf '   %sQueue is empty. Press S to search and add tracks.%s\n' "$DIM" "$R$EL"
    else
        printf '   %sQueue (%d):%s\n' "$B" "$n" "$R$EL"
        local i
        for ((i=0;i<n;i++)); do
            local mark=" " row_style="$DIM" row_end="$R"
            if (( i == QIDX && i == QCUR )); then
                mark="${GREEN}▶${R}"; row_style="${GREEN}${B}"; row_end="$R"
            elif (( i == QIDX )); then
                mark="${GREEN}▶${R}"
            elif (( i == QCUR )); then
                mark="${CYAN}▌${R}"; row_style="${CYAN}${B}"; row_end="$R"
            fi
            local tn="${QTITLE[$i]:0:$((W-14))}"
            printf '   %s %s%2d) %s%s%s\n' "$mark" "$row_style" $((i+1)) "$tn" "$row_end" "$EL"
        done
    fi
    printf '%s\n' "$EL"

    # Controls
    printf '%s%s%s\n' "$CYAN" "$border" "$R$EL"
    printf '  %sSPC%s pause   %ss%s stop   %sn%s next   %sb%s prev   %s←/→%s seek   %sm%s mute   %s+/-%svol   %s?%s help   %sEsc%s back   %sq%s quit%s\n' \
        "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$R$EL"
    printf '  %s↑/↓%s cursor   %sEnter%s play   %sS%s search+queue   %sr%s remove   %sa%s save   %sC%s save to playlist   %sl%s load saved   %sL%s edit saved   %sR%s reset session%s\n' \
        "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$R$EL"
    printf '%s%s%s\n' "$CYAN" "$border" "$R$EL"
    printf '%s' "$ED"
}

player_loop() {
    local key rest
    while true; do
        draw_player
        read -rsN 1 -t 0.05 key || key=""
        [[ -z "$key" ]] && continue

        case "$key" in
            $'\n'|$'\r')
                (( QCUR >= 0 && QCUR < ${#QURL[@]} )) && queue_play_idx "$QCUR" ;;
            ' '|p) mpv_cmd '{"command":["cycle","pause"]}' ;;
            s)     mpv_cmd '{"command":["stop"]}'; QIDX=-1; QCUR=-1; LAST_PLAYING=0 ;;
            n|'>') queue_next ;;
            b|'<') queue_prev ;;
            '+'|'=') mpv_cmd '{"command":["add","volume",5]}' ;;
            '-')   mpv_cmd '{"command":["add","volume",-5]}' ;;
            m)    mpv_cmd '{"command":["cycle","mute"]}' ;;
            S)    stty echo -icanon 2>/dev/null
                  tput cup "$(tput lines 2>/dev/null || echo 24)" 0 2>/dev/null
                  local _query=""
                  read_line "Search: " _query
                  stty -echo -icanon 2>/dev/null
                  [[ -n "$_query" ]] && do_search "$_query" ;;
            a)    save_current_to_playlist ;;
            c)    save_current_to_playlist ;;  # alias
            r)    (( QCUR < 0 || QCUR >= ${#QURL[@]} )) && continue
                  queue_remove_at "$QCUR"
                  playlist_save ;;
            R)    QURL=(); QTITLE=(); QIDX=-1; QCUR=-1
                  mpv_cmd '{"command":["stop"]}'; LAST_PLAYING=0
                  : > "$PLAYLIST_DIR/${CURRENT_PLAYLIST:-Working}.txt" ;;
            l)    QURL=(); QTITLE=(); QIDX=-1; QCUR=-1
                  mpv_cmd '{"command":["stop"]}'; LAST_PLAYING=0
                  playlist_load "${CURRENT_PLAYLIST:-Working}"
                  (( ${#QURL[@]} > 0 )) && queue_play_idx 0 ;;
            L)    edit_saved_playlist ;;
            h|'?') help_overlay_player ;;
            q|Q)   break ;;
            $'\e')
                read -rsN 2 -t 0.05 rest || true
                case "$rest" in
                    '[A') queue_cursor_up ;;
                    '[B') queue_cursor_down ;;
                    '[C') mpv_cmd '{"command":["seek",5]}' ;;
                    '[D') mpv_cmd '{"command":["seek",-5]}' ;;
                esac
                # bare Esc without a following sequence: go back to browser
                if [[ -z "$rest" ]]; then
                    SCREEN="playlists"
                    return
                fi
                ;;
            *) ;;
        esac
    done
}

# ---------- playlist browser ----------

draw_playlist_browser() {
    local R=$'\e[0m' B=$'\e[1m' DIM=$'\e[2m' CYAN=$'\e[1;36m' GREEN=$'\e[1;32m'
    local GREY=$'\e[1;90m'
    local EL=$'\e[K' ED=$'\e[J' HOME=$'\e[H'

    local names=()
    playlist_list_names names
    local n=${#names[@]}

    local cols; cols=$(tput cols 2>/dev/null || echo 80)
    local W=$cols; (( W < 60 )) && W=60
    local border; border=$(printf '━%.0s' $(seq 1 "$W"))

    echo -en "\e[?25l$HOME"

    printf '%s%s%s\n'  "$CYAN" "$border" "$R$EL"
    printf '   %sLaingard Music Player%s%s\n' \
        "$B" "$R" "$R$EL"
    printf '%s%s%s\n'  "$CYAN" "$border" "$R$EL"
    printf '   %sPlaylists%s\n' "$CYAN" "$R$EL"
    printf '%s\n' "$EL"

    if (( n == 0 )); then
        printf '   %sCreate your first playlist%s\n' "$B" "$R$EL"
        printf '   %s(Create one with %sC%s, or press %sSPACE%s to start with an empty queue)%s\n' \
            "$DIM" "$B" "$DIM" "$B" "$DIM" "$R$EL"
        printf '%s\n' "$EL"
    else
        local i
        for ((i=0;i<n;i++)); do
            local cnt; cnt=$(playlist_track_count "${names[$i]}")
            local mark=" " row_style="$DIM" row_end="$R"
            if (( i == PL_CUR )); then
                mark="${GREEN}▶${R}"
                row_style="${B}"   # bold for selected row
                row_end="$R"
            fi
            printf '   %s %s%-20s%s %s(%s track%s)%s\n' \
                "$mark" "$row_style" "${names[$i]}" "$row_end" \
                "$DIM" "$cnt" "$([[ $cnt -eq 1 ]] && echo '' || echo 's')" "$R$EL"
        done
        printf '%s\n' "$EL"
    fi

    # Small player-status line when something is already playing
    if (( ${#QURL[@]} > 0 && QIDX >= 0 )); then
        local short="${QTITLE[$QIDX]:0:$((W-20))}"
        printf '   %sNow playing:%s %s%s%s\n' "$CYAN" "$R" "$DIM" "$short" "$R$EL"
        printf '%s\n' "$EL"
    fi

    printf '%s%s%s\n' "$CYAN" "$border" "$R$EL"
    printf '  %s↑/↓%s browse   %sEnter%s open   %sSPACE%s start empty   %sC%s create playlist%s\n' \
        "$B" "$R" "$B" "$R" "$B" "$R" "$B" "$R" "$R$EL"
    printf '  %sd%s delete    %sr%s rename    %sq%s quit\n' \
        "$B" "$R" "$B" "$R" "$B" "$R$EL"
    printf '%s%s%s\n' "$CYAN" "$border" "$R$EL"
    printf '%s' "$ED"
}

playlist_browser_loop() {
    local key rest names=()
    while true; do
        playlist_list_names names
        draw_playlist_browser
        read -rsN 1 -t 0.05 key || key=""
        [[ -z "$key" ]] && continue

        case "$key" in
            $'\n'|$'\r'|' ')
                if (( ${#names[@]} == 0 )); then
                    CURRENT_PLAYLIST=""
                    QURL=(); QTITLE=(); QIDX=-1; QCUR=-1
                    SCREEN="player"; return
                fi
                if [[ "$key" == ' ' ]]; then
                    CURRENT_PLAYLIST=""
                    QURL=(); QTITLE=(); QIDX=-1; QCUR=-1
                    SCREEN="player"; return
                fi
                CURRENT_PLAYLIST="${names[$PL_CUR]}"
                playlist_load "$CURRENT_PLAYLIST"
                SCREEN="player"; return
                ;;
            'c')
                PL_CUR=0
                stty echo -icanon 2>/dev/null
                tput cup "$(tput lines 2>/dev/null || echo 24)" 0 2>/dev/null
                local _name=""
                read_line "New playlist name: " _name
                stty -echo -icanon 2>/dev/null
                [[ -z "$_name" ]] && continue
                touch "$PLAYLIST_DIR/$_name.txt"
                CURRENT_PLAYLIST="$_name"
                QURL=(); QTITLE=(); QIDX=-1; QCUR=-1
                SCREEN="player"; return
                ;;
            'd')
                (( ${#names[@]} == 0 )) && continue
                playlist_delete "${names[$PL_CUR]}"
                (( PL_CUR >= ${#names[@]} - 1 && PL_CUR > 0 )) && PL_CUR=$((PL_CUR-1))
                ;;
            'r')
                (( ${#names[@]} == 0 )) && continue
                stty echo -icanon 2>/dev/null
                tput cup "$(tput lines 2>/dev/null || echo 24)" 0 2>/dev/null
                local _new=""
                read_line "Rename '${names[$PL_CUR]}' to: " _new
                stty -echo -icanon 2>/dev/null
                [[ -z "$_new" ]] && continue
                playlist_rename "${names[$PL_CUR]}" "$_new"
                if [[ "$CURRENT_PLAYLIST" == "${names[$PL_CUR]}" ]]; then
                    CURRENT_PLAYLIST="$_new"
                fi
                ;;
            $'\e')
                read -rsN 2 -t 0.05 rest || true
                case "$rest" in
                    '[A') (( PL_CUR > 0 )) && PL_CUR=$((PL_CUR-1)) ;;
                    '[B') (( PL_CUR < ${#names[@]}-1 )) && PL_CUR=$((PL_CUR+1)) ;;
                esac
                ;;
            q|Q) break ;;
            *) ;;
        esac
    done
}

# ---------- help overlays ----------

help_overlay_player() {
    echo -en "\e[H\e[2J"
    cat <<'EOF'

  Laingard Music Player — TUI keys

  Playback
    SPACE / p      play / pause
    s              stop (return to idle; keeps queue)
    n  /  >        next track
    b  /  <        previous track
    ←  /  →        seek ±5s

  Queue
    ↑  /  ↓        move cursor through the queue
    Enter          play the track under the cursor
    r              remove the track under the cursor
    S              search YouTube (fzf) → queue & play
    a / c          save current track to the current playlist

  Library
    l              (re)load current playlist from disk
    L              edit current playlist (fzf; Ctrl-D delete, Enter queue & play)
    R              reset queue + stop
    Esc            back to playlist browser

  Volume
    +  /  =        volume up            -  volume down
    m              toggle mute

  Misc
    h  /  ?        this help
    q              quit player
EOF
    echo -e "\n  Press any key to return."
    read -rsN 1 -t 60 _ || true
}

show_help_static() {
    cat <<EOF
Usage: $0 [option] [argument]
  (no arg)         full TUI player (recommended)
  -s, --search 't' search via fzf; add to queue and play
  -p, --play       play saved playlist file (non-TUI, mpv takes over)
  -l, --list       edit saved playlist via fzf
  -a, --add        add currently playing track to saved playlist
  -h, --help       this message

TUI keys (inside the player):
  Playback:  SPACE/p pause   s stop    n/> next   b/< prev   ←/→ seek ±5s
  Queue:     ↑/↓ navigate cursor   Enter play cursor   S search+queue
             r remove cursor item   a/c save current track
  Volume:    +/- change      m mute
  Library:   l load saved    L edit saved    R reset session    Esc back to playlists
  Misc:      ? help          q/Esc quit
EOF
}

# ---------- legacy paths (non-TUI) ----------

legacy_play_playlist() {
    local f="$PLAYLIST_DIR/Working.txt"
    [[ -s "$f" ]] || { echo "Empty playlist :("; return; }
    local urls; urls=$(cut -d '#' -f1 "$f")
    mpv --no-video --cache=yes --cache-secs=30 --demuxer-max-bytes=500M \
        --no-sub --sid=0 --ytdl-format="$YTDLP_FORMAT" \
        --playlist=<(printf '%s\n' "$urls")
}

legacy_add() {
    [[ -f /tmp/current_playing.txt && -s /tmp/current_playing.txt ]] || { echo "Play something first."; return; }
    local url title
    url=$(</tmp/current_playing.txt)
    title=$(yt-dlp --no-warnings --get-title "$url" 2>/dev/null) || title="$url"
    echo "$url # $title" >> "$WORKING_PLAYLIST"
    echo "Added to Working playlist."
}

# ---------- entrypoint ----------

trap 'restore_term; mpv_end' EXIT INT TERM

case "${1:-}" in
    -h|--help) show_help_static ;;
    -p|--play) legacy_play_playlist ;;
    -a|--add)  legacy_add ;;
    -l|--list)
        init_term
        mpv_start || { echo "Cannot start mpv" >&2; exit 1; }
        CURRENT_PLAYLIST="Working"
        playlist_load "$CURRENT_PLAYLIST"
        edit_saved_playlist
        ;;
    -s|--search)
        if [[ -n "${2:-}" ]]; then
            init_term
            mpv_start || { echo "Cannot start mpv" >&2; exit 1; }
            do_search "$2"
            [[ "${#QURL[@]}" -gt 0 ]] && player_loop
        else
            echo "Error: you must provide a song title"; show_help_static
        fi
        ;;
    "")
        init_term
        mpv_start || { echo "Cannot start mpv" >&2; exit 1; }
        # Browser → player → browser navigation loop.
        # browser_loop returns when a playlist is selected (SCREEN="player")
        # or when the user quits (SCREEN="playlists"). player_loop returns
        # on Esc (SCREEN="playlists") or q (SCREEN="player").
        while true; do
            playlist_browser_loop
            [[ "$SCREEN" == "playlists" ]] && break
            player_loop
            [[ "$SCREEN" == "playlists" ]] || break
        done
        ;;
    *)
        echo "Not a valid option"; show_help_static ;;
esac
