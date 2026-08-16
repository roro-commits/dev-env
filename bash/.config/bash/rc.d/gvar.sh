#@ 50 gitlab - variables
# Project CI/CD variables.
#
# This is the one surface here where a mistake breaks the pipeline for
# everyone, and where the values are secrets. Three rules follow:
#   - masked and protected flags are shown, never guessed at
#   - values are never printed unless you ask for one explicitly
#   - every write is confirmed; delete needs the key typed back

# key, scope, flags - never the value.
_gvar_list() {
    _g_api variables '?per_page=100' \
        | jq -r '.[] | [.key,
                        (.environment_scope // "*"),
                        (if .masked    then "masked"    else "-" end),
                        (if .protected then "protected" else "-" end),
                        .variable_type] | @tsv' \
        | sort \
        | awk -F'\t' '{ printf "%-32s %-12s %-8s %-10s %s\n", $1, $2, $3, $4, $5 }'
}

#: gvar [action]         project CI/CD variables
#>   gvar                  list keys, scope and flags - never values
#>   gvar browse           same list, pick one to get, set or delete it
#>   gvar get KEY          print one value (only way to see one)
#>   gvar get KEY > f      a file variable's contents, back onto disk
#>   gvar set KEY          create or update, prompting for value and flags
#>   gvar rm KEY           delete, after typing the key back
#>
#>   env_var   the value becomes an environment variable in the job
#>   file      the value is written to a temp file and the variable holds
#>             its path - for kubeconfigs, certs, service-account JSON.
#>             set reads these from a path on disk, not from a prompt
#>   masked    hidden in job logs. requires a single line, 8+ chars, and a
#>             restricted character set - so file variables cannot be masked
#>   protected only exposed to protected branches and tags
#>
#>   a value you paste here goes to the server and stays there. for anything
#>   you would not want in shell history, use `gvar set KEY` and paste at the
#>   prompt rather than putting it on the command line
gvar() {
    _g_ready || return 1

    case "${1:-list}" in
        list|l)   _gvar_list ;;
        browse|b) _gvar_browse ;;
        get|g)    shift; _gvar_get "${1:-}" ;;
        set|s)    shift; _gvar_set "${1:-}" ;;
        rm|del|d) shift; _gvar_rm "${1:-}" ;;
        *)        echo "gvar: unknown action '$1' (list browse get set rm)" >&2; return 1 ;;
    esac
}

# Same list as `gvar`, but you can act on a row. Loops: acting on one variable
# returns you to the list, esc leaves.
_gvar_browse() {
    local line key action
    while true; do
        line=$(_gvar_list | pick --prompt='variable> ' --height=60% \
                  --header='enter: actions   esc: quit') || return 0
        [ -n "$line" ] || return 0
        key=${line%% *}

        action=$(menu_pick "$key
  $line
" get set delete back) || continue

        case $action in
            get)    _gvar_get "$key" ;;
            set)    _gvar_set "$key" ;;
            delete) _gvar_rm  "$key" ;;
            back)   continue ;;
        esac

        read -r -p "enter to return to the list... " _ </dev/tty
    done
}

_gvar_get() {
    local key=$1
    [ -n "$key" ] || { key=$(_gvar_list | pick --prompt='key> ' --height=50%) || return 1
                       key=${key%% *}; }
    [ -n "$key" ] || return 1

    _g_api "variables/$key" | jq -r '.value'
}

_gvar_set() {
    local key=$1 value vtype src masked protected scope existing method answer

    [ -n "$key" ] || read -r -e -p "key: " key </dev/tty
    [ -n "$key" ] || { echo "gvar: no key" >&2; return 1; }

    # Create and update are different verbs in the API, so find out which.
    if _g_api "variables/$key" 2>/dev/null | jq -e '.key' >/dev/null 2>&1; then
        existing=yes; method=PUT
        echo "$key exists - this will overwrite it"
    else
        existing=no;  method=POST
    fi

    vtype=$(menu_pick "variable type" env_var file) || return 1

    if [ "$vtype" = file ]; then
        # A file variable is usually a kubeconfig, a cert or a key: multi-line,
        # already on disk. GitLab writes it to a temp file in the job and sets
        # the variable to that path.
        read -r -e -p "path to file: " src </dev/tty
        src=${src/#\~/$HOME}
        [ -f "$src" ] || { echo "gvar: no file at $src" >&2; return 1; }
        value=$(cat "$src")
        printf '%s bytes, %s lines\n' "$(wc -c < "$src")" "$(wc -l < "$src")"
    else
        # -s keeps the value off the screen and out of shell history.
        read -r -s -p "value (hidden): " value </dev/tty; echo
    fi
    [ -n "$value" ] || { echo "gvar: no value" >&2; return 1; }

    if [ "$vtype" = file ]; then
        # GitLab only masks single-line values within a restricted charset,
        # so a file variable effectively cannot be masked.
        masked=no
        echo "masked: not available for file variables"
    else
        masked=$(menu_pick "masked in job logs?" no yes) || return 1
    fi
    protected=$(menu_pick "protected branches only?" no yes) || return 1

    read -r -e -i "*" -p "environment scope: " scope </dev/tty

    printf '\n  %s %s (%s)\n  masked=%s protected=%s scope=%s\n\n' \
        "$([ "$existing" = yes ] && echo update || echo create)" \
        "$key" "$vtype" "$masked" "$protected" "$scope"
    read -r -p "run this? [y/N] " answer </dev/tty
    [ "$answer" = y ] || { echo "cancelled"; return 1; }

    local proj path
    proj=$(_g_project) || return 1
    path="projects/$proj/variables"
    [ "$method" = PUT ] && path="$path/$key"

    glab api -X "$method" "$path" \
        -f "key=$key" -f "value=$value" -f "variable_type=$vtype" \
        -f "masked=$([ "$masked" = yes ] && echo true || echo false)" \
        -f "protected=$([ "$protected" = yes ] && echo true || echo false)" \
        -f "environment_scope=$scope" \
        | jq -r '"\(.key)  \(.variable_type)  masked=\(.masked)  protected=\(.protected)  scope=\(.environment_scope)"'
}

_gvar_rm() {
    local key=$1 typed proj

    [ -n "$key" ] || { key=$(_gvar_list | pick --prompt='delete> ' --height=50%) || return 1
                       key=${key%% *}; }
    [ -n "$key" ] || return 1

    echo "deleting $key. Any pipeline that reads it will start failing."
    read -r -p "type the key to confirm: " typed </dev/tty
    [ "$typed" = "$key" ] || { echo "cancelled"; return 1; }

    proj=$(_g_project) || return 1
    glab api -X DELETE "projects/$proj/variables/$key" >/dev/null && echo "$key deleted"
}
