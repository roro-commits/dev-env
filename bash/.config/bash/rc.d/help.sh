#@ 90 help
# Help index and command menu. Loaded last so it sees every command.

# --- help ------------------------------------------------------------------

#: dev-help [name]       list commands, or examples for one
#>   dev-help
#>   dev-help pclone       examples for pclone only

# dev-help   print every line marked with #: in this file
# Every documented line, in load order. dev-help and m both read this.
_dev_doc() {
    cat "$DEV_RC_DIR"/*.sh
}

# shellcheck disable=SC2120   # optional arg comes from the user, not this file
dev-help() {
    local out f title

    if [ -z "${1:-}" ]; then
        # Grouped: 29 flat lines is a wall. Each rc.d file declares its own
        # heading with #@ <sort> <title>, so a new file joins the list by
        # existing, not by being registered anywhere.
        for f in $(grep -l '^#@' "$DEV_RC_DIR"/*.sh 2>/dev/null \
                   | while read -r x; do
                         printf '%s\t%s\n' "$(sed -n 's/^#@ \([0-9]*\) .*/\1/p;q' "$x")" "$x"
                     done | sort -n | cut -f2); do
            title=$(sed -n 's/^#@ [0-9]* //p;q' "$f")
            printf '\n  %s\n' "$title"
            grep '^#:' "$f" | cut -c4- | sed 's/^/    /'
        done
        printf '\n  dev-help p        examples for one command\n\n'
        return
    fi

    out=$(_dev_doc | awk -v want="$1" '
        /^#:/     { hit = ($2 == want) }
        !/^#[:>]/ { hit = 0; next }
        hit       { sub(/^#[:>] ?/, ""); print }
    ')

    if [ -z "$out" ]; then
        echo "dev-help: no command named $1" >&2
        return 1
    fi
    printf '%s\n' "$out"
}

#: m                     pick a command from a menu and run it
#>   m                     type to filter, enter to run
#>
#>   loops: after a command finishes, enter brings the menu back and
#>   ctrl-c stops. esc at the menu quits.
#>   group headings are shown but not selectable

# m   pick a command from the #: list, prompt for an argument, run it
m() {
    local line cmd args

    # Loops: running a command returns you to the menu, esc leaves. Without
    # this the menu ends after one command and you land at the prompt, which
    # is exactly what a menu should not do.
    while true; do
        # shellcheck disable=SC2119   # deliberate: the menu wants the summary
        line=$(dev-help | grep -v '^  *$' | grep -v 'examples for one command' \
               | sed 's/^    //' \
               | fzf --prompt='cmd> ' --height=60% \
                     --header='enter: run it   esc: quit') || return 0
        [ -n "$line" ] || return 0

        # Headings keep their two-space indent, so ${line%% *} yields "" for
        # them and type rejects it. One guard covers both cases.
        cmd=${line%% *}
        type -t "$cmd" >/dev/null 2>&1 || continue

        args=
        case $line in
            *'<'*) read -r -e -p "$cmd - argument required: " args </dev/tty
                   [ -n "$args" ] || continue ;;
            *'['*) read -r -e -p "$cmd - argument (blank for none): " args </dev/tty ;;
        esac

        echo "+ $cmd $args"
        eval "$cmd $args"

        printf '\n[enter for the menu, ctrl-c to stop] '
        read -r </dev/tty || return 0
    done
}
