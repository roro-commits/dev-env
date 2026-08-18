#@ 80 zellij
# One session per project, and a way to throw any command into a floating pane.
#
# The point is that a session outlives a terminal window. Come back tomorrow,
# `zj 5`, and the panes, the working directory and the scrollback are where you
# left them - which is most of the context you would otherwise rebuild.

# Session names cannot contain dots or spaces, and 05-rotimi.cloud has both
# problems waiting to happen.
# zellij list-sessions colours its output, which breaks both name matching and
# ${s%% *}. --no-formatting is the supported way off; the sed is a fallback for
# older builds that lack the flag.
_zj_sessions() {
    zellij list-sessions --no-formatting 2>/dev/null \
        || zellij list-sessions 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g'
}

ZJ_LAYOUT_DIR="${ZJ_LAYOUT_DIR:-$HOME/.config/zellij/layouts}"

_zj_name() { printf '%s\n' "${1//[^a-zA-Z0-9_-]/-}"; }

# Inside a session? zellij exports several markers and which ones survive
# depends on how the pane was spawned, so check all of them.
_zj_inside() {
    [ -n "${ZELLIJ:-}${ZELLIJ_SESSION_NAME:-}${ZELLIJ_PANE_ID:-}" ]
}

# Attach, switch, or create - whichever applies. Attaching from inside a
# session nests zellij inside zellij, which is the wrong thing every time.
_zj_attach() {
    local name=$1

    if _zj_inside; then
        # Newest zellij switches directly.
        if zellij action switch-session "$name" 2>/dev/null; then
            return 0
        fi

        # Older builds cannot, but most can open the session manager plugin,
        # which switches for you. Better than printing a keybinding.
        if zellij action launch-or-focus-plugin zellij:session-manager \
               --floating 2>/dev/null; then
            echo "zj: this zellij cannot switch directly - opened the session" >&2
            echo "    manager instead. Pick '$name' there." >&2
            return 0
        fi

        echo "zj: inside session ${ZELLIJ_SESSION_NAME:-?}, and this zellij" >&2
        echo "    ($(zellij --version 2>/dev/null || echo 'version unknown'))" >&2
        echo "    can neither switch nor open the session manager." >&2
        echo "    Detach with Ctrl-o d, then: zj $name" >&2
        return 1
    fi

    if _zj_sessions | awk '{print $1}' | grep -qx "$name"; then
        zellij attach "$name"
    elif [ -f "$ZJ_LAYOUT_DIR/$name.kdl" ]; then
        # A layout named after the project wins: arrange the panes once,
        # zjsave it, and every future session for that project starts there.
        zellij --session "$name" --layout "$name"
    else
        zellij --session "$name"
    fi
}

#: zj [n|name]           attach to this project's zellij session, or make it
#>   zj                    a session named after the directory you are in
#>   zj 5                  cd to project 05 and attach to its session
#>   zj notes              a session by name, created if missing
#>
#>   a session per project means switching context is one command and the
#>   panes survive closing the terminal
#>
#>   from inside a session it switches rather than nesting. how depends on
#>   your zellij version: newest switches directly, older opens the session
#>   manager for you, oldest asks you to detach first (Ctrl-o d).
#>   zellij --version to see which you have - it can differ per machine
#>   if your nixpkgs pins differ
zj() {
    command -v zellij >/dev/null || { echo "zj: zellij not installed" >&2; return 1; }

    local target name
    if [ -z "${1:-}" ]; then
        target=$PWD
    elif [[ $1 =~ ^[0-9]+$ ]]; then
        p "$1" || return 1                 # reuse the project jump
        target=$PWD
    else
        target=$1
    fi

    name=$(_zj_name "$(basename "$target")")
    _zj_attach "$name"
}

#: zjl [-p]              pick a session and attach to it
#>   zjl                   choose from the list
#>   zjl -p                just print them, for piping
zjl() {
    command -v zellij >/dev/null || { echo "zjl: zellij not installed" >&2; return 1; }

    case "${1:-}" in
        -p|--plain) _zj_sessions; return ;;
    esac

    local s
    s=$(_zj_sessions | pick --prompt='session> ' --height=50% \
            --header='enter: attach   esc: cancel') || return 0
    [ -n "$s" ] || return 0
    _zj_attach "${s%% *}"
}

#: zjk [what]            remove sessions, running or exited
#>   zjk                   pick any number with tab, then enter
#>   zjk notes             one by name
#>   zjk --dead            every exited session, the usual clean-up
#>   zjk --all             everything, running included
#>
#>   zellij keeps exited sessions around so you can resurrect them, which is
#>   why they pile up. kill-session stops a running one; delete-session
#>   removes a dead one. zjk does whichever applies.
#>
#>   guard rails: the session you are in is skipped; exited ones need only
#>   a y; killing a RUNNING one needs the word "kill" typed out, because it
#>   may hold an editor with unsaved work. --all needs "kill-all".
zjk() {
    command -v zellij >/dev/null || { echo "zjk: zellij not installed" >&2; return 1; }

    local picks
    case "${1:-}" in
        --dead)
            zellij delete-all-sessions --yes 2>/dev/null \
                || zellij delete-all-sessions
            return ;;
        --all)
            local answer
            echo "This kills every session, running ones included."
            read -r -p "type kill-all to confirm: " answer </dev/tty
            [ "$answer" = kill-all ] || { echo "cancelled"; return 1; }
            zellij kill-all-sessions --yes 2>/dev/null \
                || zellij kill-all-sessions
            zellij delete-all-sessions --yes 2>/dev/null
            return ;;
        "")
            # Loops: the list refreshes after each removal, esc leaves.
            while true; do
                mapfile -t picks < <(_zj_sessions \
                    | pick --multi --prompt='remove> ' --height=60% \
                           --header='tab: select several   enter: remove   esc: back')
                [ ${#picks[@]} -gt 0 ] || return 0
                _zj_remove "${picks[@]}"
            done ;;
        *)
            _zj_remove "$1" ;;
    esac
}

# Exited sessions hold nothing. Running ones may hold an editor with unsaved
# work, so they are confirmed separately and more loudly.
_zj_remove() {
    local s name live=() dead=() skipped=() answer

    for s in "$@"; do
        name=${s%% *}
        [ -n "$name" ] || continue

        if [ "$name" = "${ZELLIJ_SESSION_NAME:-}" ]; then
            skipped+=("$name")
        elif printf '%s\n' "$s" | grep -q 'EXITED'; then
            dead+=("$name")
        else
            live+=("$name")
        fi
    done

    [ ${#skipped[@]} -gt 0 ] && \
        printf 'skipping %s - you are in it\n' "${skipped[*]}"

    if [ ${#dead[@]} -gt 0 ]; then
        printf 'exited, nothing to lose: %s\n' "${dead[*]}"
    fi

    if [ ${#live[@]} -gt 0 ]; then
        printf '\nRUNNING: %s\n' "${live[*]}"
        printf 'These have live processes. Anything unsaved in an editor there\n'
        printf 'is gone - detaching is safe, this is not.\n'
        read -r -p "type kill to confirm: " answer </dev/tty
        if [ "$answer" != kill ]; then
            echo "cancelled - nothing removed"
            return 1
        fi
    elif [ ${#dead[@]} -gt 0 ]; then
        read -r -p "remove them? [y/N] " answer </dev/tty
        [ "$answer" = y ] || { echo "cancelled"; return 1; }
    else
        return 0
    fi

    for name in "${live[@]}" "${dead[@]}"; do
        zellij kill-session   "$name" 2>/dev/null
        zellij delete-session "$name" 2>/dev/null
        echo "removed $name"
    done
}

#: zf [-c] <command...>  run something in a floating pane
#>   zf gnow               runs it, then leaves a shell in the pane
#>   zf gpipe              the pipeline browser, floating
#>   zf -c lazygit         close the pane when it exits instead
#>
#>   by default the pane stays: the command runs, then you get an
#>   interactive shell in the same directory, so the output is still there
#>   and you can keep working. -c closes it.
#>
#>   only works from inside a zellij session
zf() {
    _zj_inside || { echo "zf: not inside a zellij session" >&2; return 1; }

    local close=0
    case "${1:-}" in
        -c|--close) close=1; shift ;;
    esac
    [ $# -gt 0 ] || { echo "usage: zf [-c] <command...>" >&2; return 1; }

    # -ilc so the rc files load and these functions exist in the new pane.
    if [ "$close" -eq 1 ]; then
        zellij run --floating --close-on-exit -- bash -ilc "$*"
    else
        # exec bash -i leaves a usable shell where the command was, in the same
        # directory. The pane becomes somewhere to keep working rather than
        # something that vanishes the moment the command finishes.
        zellij run --floating -- bash -ilc "$* ; exec bash -i"
    fi
}

#: zjwhere               am I inside zellij, and which session
#>   zjwhere               prints the session, or says you are outside
#>
#>   worth checking when zj refuses or when you suspect nesting: two status
#>   bars at the bottom of the screen means zellij inside zellij
zjwhere() {
    if _zj_inside; then
        printf 'inside zellij\n  session %s\n  pane    %s\n' \
            "${ZELLIJ_SESSION_NAME:-?}" "${ZELLIJ_PANE_ID:-?}"
    else
        echo "not inside zellij"
    fi
}

#: zjsave [name]         freeze the current pane arrangement as a layout
#>   zjsave                save as the current session name, so `zj` reuses it
#>   zjsave dev            save under a name, use with zellij --layout dev
#>
#>   arrange the panes by hand once, then save. zj uses a layout matching the
#>   project name automatically, so 05-rotimi-cloud.kdl becomes how that
#>   project always opens.
#>
#>   it writes into the dev-env tree and stows it, so the layout is version
#>   controlled with everything else. three ways to make one stick:
#>     zjsave                        per project, picked up by zj
#>     default_layout "dev"          in config.kdl, for every new session
#>     session_serialization true    zellij restores exited sessions as they were
zjsave() {
    _zj_inside || { echo "zjsave: run this from inside the session to save" >&2; return 1; }

    local name=${1:-${ZELLIJ_SESSION_NAME:-}} dest
    name=$(_zj_name "$name")
    [ -n "$name" ] || { echo "zjsave: no name" >&2; return 1; }

    dest="$DEV_ENV/zellij/.config/zellij/layouts/$name.kdl"
    mkdir -p "$(dirname "$dest")" || return 1

    if ! zellij action dump-layout > "$dest" 2>/dev/null; then
        rm -f "$dest"
        echo "zjsave: this zellij has no 'action dump-layout'" >&2
        return 1
    fi

    if [ ! -s "$dest" ]; then
        rm -f "$dest"
        echo "zjsave: dump-layout produced nothing" >&2
        return 1
    fi

    ( cd "$DEV_ENV" && stow --no-folding -R -t "$HOME" zellij >/dev/null 2>&1 )
    echo "saved $name.kdl - new sessions named $name will use it"
}

#: zjlayouts [-p]        pick a saved layout and start a session with it
#>   zjlayouts             choose one, preview it, start a session
#>   zjlayouts -p          just print the names
#>
#>   it asks for a session name, defaulting to the layout name, so you can
#>   run the same layout twice for different work
zjlayouts() {
    local names layout session
    # Only files that actually declare a layout: a stray .kdl in this
    # directory is not something you can start a session with.
    names=$(for f in "$ZJ_LAYOUT_DIR"/*.kdl; do
                [ -e "$f" ] || continue
                grep -q '^[[:space:]]*layout' "$f" || continue
                basename "$f" .kdl
            done)

    [ -n "$names" ] || { echo "no layouts in $ZJ_LAYOUT_DIR"; return 0; }

    case "${1:-}" in
        -p|--plain) printf '%s\n' "$names"; return ;;
    esac

    command -v zellij >/dev/null || { echo "zjlayouts: zellij not installed" >&2; return 1; }

    layout=$(printf '%s\n' "$names" \
             | pick --prompt='layout> ' --height=50% \
                    --preview="cat $ZJ_LAYOUT_DIR/{}.kdl" \
                    --preview-window=right:60%:wrap \
                    --header='enter: start a session with it   esc: cancel') || return 0
    [ -n "$layout" ] || return 0

    if _zj_inside; then
        echo "zjlayouts: detach first (Ctrl-o d) - a layout starts a session" >&2
        return 1
    fi

    read -r -e -i "$layout" -p "session name: " session </dev/tty
    [ -n "$session" ] || return 1

    zellij --session "$(_zj_name "$session")" --layout "$layout"
}
