#@ 70 focus
# Focus blocks and a scoreboard.
#
# "You cannot score when the match is over." The number has to be visible while
# you can still act on it, so `board` runs at shell start and `focus status`
# shows the running block, not a report written afterwards.
#
# Blocks are 90 minutes by default: Malotaux's two-thirds rule, 17 blocks a
# week, ~25 hours of actual planned work.

FOCUS_LOG="${FOCUS_LOG:-${XDG_DATA_HOME:-$HOME/.local/share}/focus.tsv}"
FOCUS_MINUTES="${FOCUS_MINUTES:-90}"
FOCUS_WEEK_TARGET="${FOCUS_WEEK_TARGET:-17}"
FOCUS_CURRENT="${XDG_RUNTIME_DIR:-/tmp}/focus.current"

# --- internal ---------------------------------------------------------------

_focus_hm() { printf '%dh%02dm' $(( $1 / 60 )) $(( $1 % 60 )); }

_focus_today()     { awk -F'\t' -v d="$(date +%F)" '$1 == d { n += $4 } END { print n + 0 }' "$FOCUS_LOG" 2>/dev/null; }
_focus_today_n()   { awk -F'\t' -v d="$(date +%F)" '$1 == d { n++ }    END { print n + 0 }' "$FOCUS_LOG" 2>/dev/null; }
_focus_week_n()    { awk -F'\t' -v w="$(date +%G-W%V)" \
                       '{ cmd = "date -d " $1 " +%G-W%V"; cmd | getline x; close(cmd)
                          if (x == w) n++ } END { print n + 0 }' "$FOCUS_LOG" 2>/dev/null; }

# Consecutive days, counting back from today, with at least one block.
_focus_streak() {
    [ -f "$FOCUS_LOG" ] || { echo 0; return; }
    local d n=0
    for i in $(seq 0 365); do
        d=$(date -d "-$i day" +%F)
        if grep -q "^$d	" "$FOCUS_LOG"; then
            n=$((n + 1))
        elif [ "$i" -gt 0 ]; then
            break
        fi
    done
    echo "$n"
}

# --- commands ---------------------------------------------------------------

#: focus [note]          start a 90 minute block; focus end to close it
#>   focus                 start a block
#>   focus "drm-4511 signing"   start one with a label
#>   focus status          how long the running block has left
#>   focus end [note]      close it and record the minutes
#>
#>   running over is not an error - if you were in it, keep the extra.
#>   focus end asks, because "a 130 minute block" and "90 minutes plus 40
#>   of drift" are different facts and only you know which happened
#>   focus log [n]         recent blocks
#>
#>   the target is 17 blocks a week - two thirds of the working week, which
#>   is the most anyone plans accurately (Malotaux). the rest is the
#>   interruptions you cannot schedule
focus() {
    case "${1:-start}" in
        status|s) _focus_status ;;
        end|e)    shift; _focus_end "$*" ;;
        log|l)    shift; _focus_log "${1:-10}" ;;
        *)        _focus_start "$*" ;;
    esac
}

_focus_start() {
    if [ -f "$FOCUS_CURRENT" ]; then
        echo "a block is already running:"
        _focus_status
        return 1
    fi
    printf '%s\t%s\n' "$(date +%s)" "${1:-}" > "$FOCUS_CURRENT"
    printf 'block started, %s minutes. %s\n' "$FOCUS_MINUTES" "${1:-}"
    printf 'today: %s blocks   this week: %s of %s\n' \
        "$(_focus_today_n)" "$(_focus_week_n)" "$FOCUS_WEEK_TARGET"
}

_focus_status() {
    [ -f "$FOCUS_CURRENT" ] || { echo "no block running"; return 1; }

    local start note elapsed left
    IFS=$'\t' read -r start note < "$FOCUS_CURRENT"
    elapsed=$(( ($(date +%s) - start) / 60 ))
    left=$(( FOCUS_MINUTES - elapsed ))

    if [ "$left" -gt 0 ]; then
        printf '%s elapsed, %s left   %s\n' \
            "$(_focus_hm "$elapsed")" "$(_focus_hm "$left")" "$note"
    else
        printf '%s elapsed - over by %s   %s\n' \
            "$(_focus_hm "$elapsed")" "$(_focus_hm $(( -left )))" "$note"
    fi
}

_focus_end() {
    [ -f "$FOCUS_CURRENT" ] || { echo "no block running"; return 1; }

    local start note minutes over answer
    IFS=$'\t' read -r start note < "$FOCUS_CURRENT"
    minutes=$(( ($(date +%s) - start) / 60 ))
    [ -n "${1:-}" ] && note=$1

    # Overrunning is usually the good case - you were in it. Ask rather than
    # silently recording 130 minutes as one 90 minute block, because the two
    # answers mean different things: a long block, or a block plus drift.
    over=$(( minutes - FOCUS_MINUTES ))
    if [ "$over" -gt 5 ]; then
        printf 'ran %s over. keep the extra? [Y/n] ' "$(_focus_hm "$over")"
        # -r on /dev/tty lies in some containers; try actually opening it.
        if { : </dev/tty; } 2>/dev/null
        then read -r answer </dev/tty
        else read -r answer
        fi
        if [ "$answer" = n ]; then
            minutes=$FOCUS_MINUTES
            echo "recorded as $FOCUS_MINUTES minutes"
        fi
    fi

    mkdir -p "$(dirname "$FOCUS_LOG")"
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(date +%F)" "$(date -d "@$start" +%H:%M)" "$(date +%H:%M)" \
        "$minutes" "${note//$'\t'/ }" >> "$FOCUS_LOG"
    rm -f "$FOCUS_CURRENT"

    printf 'block closed: %s   %s\n' "$(_focus_hm "$minutes")" "$note"
    printf 'today: %s blocks, %s   this week: %s of %s\n' \
        "$(_focus_today_n)" "$(_focus_hm "$(_focus_today)")" \
        "$(_focus_week_n)" "$FOCUS_WEEK_TARGET"
}

_focus_log() {
    [ -f "$FOCUS_LOG" ] || { echo "no blocks logged yet"; return 0; }
    tail -n "$1" "$FOCUS_LOG" \
        | awk -F'\t' '{ printf "%s  %s-%s  %3dm  %s\n", $1, $2, $3, $4, $5 }'
}

#: board                 today's numbers, while you can still change them
#>   board                 blocks, streak, open failure records
#>   add to home.nix initExtra to see it in every new shell
#>
#>   deliberately shows what is still open rather than what is finished:
#>   a score you can no longer influence is a report, not a scoreboard
board() {
    local blocks week streak openrecs bar filled i row running
    local W=46                       # inner width; every row is padded to it

    blocks=$(_focus_today_n)
    week=$(_focus_week_n)
    streak=$(_focus_streak)
    openrecs=$(awk -F'\t' '$9 == "open"' "${GFAIL_INDEX:-/nonexistent}" 2>/dev/null | wc -l)

    filled=$(( week * 20 / FOCUS_WEEK_TARGET ))
    [ "$filled" -gt 20 ] && filled=20
    bar=""
    for ((i = 0; i < 20; i++)); do
        if [ "$i" -lt "$filled" ]; then bar="$bar#"; else bar="$bar."; fi
    done

    # One helper so no row can drift out of alignment.
    _row() {
        local w=$((W - 4)) t=$1
        [ ${#t} -gt "$w" ] && t="${t:0:$((w - 1))}~"     # truncate, never overflow
        printf '   |  %-*s  |\n' "$w" "$t"
    }

    printf '\n   +%s+\n' "$(printf '%*s' "$W" '' | tr ' ' '-')"
    _row "$(date '+%A %d %B')"
    printf '   |%s|\n' "$(printf '%*s' "$W" '' | tr ' ' '-')"
    printf -v row 'week   [%s] %s/%s' "$bar" "$week" "$FOCUS_WEEK_TARGET"
    _row "$row"
    printf -v row 'today  %s blocks   streak %s days' "$blocks" "$streak"
    _row "$row"
    [ "$openrecs" -gt 0 ] && _row "$openrecs open failure record(s) - gfail fix"
    if [ -f "$FOCUS_CURRENT" ]; then
        running=$(_focus_status)
        _row "running: $running"
    fi
    printf '   +%s+\n\n' "$(printf '%*s' "$W" '' | tr ' ' '-')"
    unset -f _row
}
