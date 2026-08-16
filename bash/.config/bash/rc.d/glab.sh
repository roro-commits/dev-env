#@ 40 gitlab - pipelines and jobs
# GitLab from the terminal. These commands resolve an id interactively and
# then hand off to glab; they are a navigation layer, not an API client.
#
# Rule: select with `glab api` (stable JSON), act with `glab` (stable CLI).
# Parsing `glab ci list` human output breaks across releases.

# --- foundations ------------------------------------------------------------

# Host of the current repo's origin, e.g. gitlab.com or git-gdd.sdo.jlrmotor.com
_g_host() {
    local url
    url=$(git remote get-url origin 2>/dev/null) || return 1
    case $url in
        git@*)     printf '%s\n' "${url#git@}"   | cut -d: -f1 ;;
        ssh://*)   printf '%s\n' "${url#ssh://}" | sed 's|^[^@]*@||; s|[:/].*||' ;;
        http*://*) printf '%s\n' "$url" | sed 's|^[a-z]*://||; s|^[^@]*@||; s|/.*||' ;;
        *)         return 1 ;;
    esac
}

# Project path URL-encoded for the API, e.g. group%2Fsub%2Fproject
# Memoised per directory: this runs on every _g_api call and the answer cannot
# change without changing directory or editing the remote.
_G_PROJ_CACHE_DIR=
_G_PROJ_CACHE_VAL=
_g_project() {
    local url path

    # An explicit target wins over the git remote, so every g* command can be
    # pointed at another repo without leaving this one. Set by grepo.
    if [ -n "${GLAB_PROJECT:-}" ]; then
        printf '%s\n' "${GLAB_PROJECT//\//%2F}"
        return 0
    fi

    if [ "$_G_PROJ_CACHE_DIR" = "$PWD" ] && [ -n "$_G_PROJ_CACHE_VAL" ]; then
        printf '%s\n' "$_G_PROJ_CACHE_VAL"
        return 0
    fi
    url=$(git remote get-url origin 2>/dev/null) || return 1
    case $url in
        git@*)     path=${url#*:} ;;
        ssh://*)   path=$(printf '%s\n' "${url#ssh://}" | sed 's|^[^/]*/||') ;;
        http*://*) path=$(printf '%s\n' "$url" | sed 's|^[a-z]*://[^/]*/||') ;;
        *)         return 1 ;;
    esac
    path=${path%.git}
    path=${path#/}
    _G_PROJ_CACHE_DIR=$PWD
    _G_PROJ_CACHE_VAL=${path//\//%2F}
    printf '%s\n' "$_G_PROJ_CACHE_VAL"
}

# GET a project-scoped API path: _g_api pipelines '?per_page=20'
_g_api() {
    local proj
    proj=$(_g_project) || { echo "not a GitLab remote" >&2; return 1; }
    glab api "projects/$proj/$1$2"
}

# Is this remote actually a GitLab instance? Cheap check first (known
# non-GitLab hosts), then probe /api/v4/version, which only GitLab serves.
_g_is_gitlab() {
    local host=$1
    case $host in
        github.com|*.github.com|bitbucket.org|codeberg.org|*.sr.ht) return 1 ;;
    esac
    curl -fsS --max-time 5 "https://$host/api/v4/version" >/dev/null 2>&1
}

# Guard: everything below needs these three
_g_ready() {
    command -v glab >/dev/null || { echo "glab not installed" >&2; return 1; }
    command -v jq   >/dev/null || { echo "jq not installed" >&2; return 1; }
    git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo" >&2; return 1; }
}

# --- colour -----------------------------------------------------------------
# Status colour, honoured by every list. NO_COLOR=1 turns it all off
# (https://no-color.org). The awk snippet is shared rather than repeated.
# NOTE: no isatty check here. This function is always called inside "$(...)",
# so its own stdout is a pipe, and the lists it feeds go into fzf, which is
# also a pipe. Testing -t 1 anywhere in that chain is always false, which is
# exactly the bug that made colour never appear. NO_COLOR is the only switch.
_g_colour_awk() {
    if [ -n "${NO_COLOR:-}" ]; then
        printf '%s' 'function col(s) { return "" } function off() { return "" }'
    else
        printf '%s' '
            function col(s) {
                s = tolower(s)
                if (s ~ /success|passed|merged|fixed/)      return "\033[32m"
                if (s ~ /failed|failure|canceled|cancelled/) return "\033[31m"
                if (s ~ /running|pending|created|preparing/) return "\033[33m"
                if (s ~ /manual|skipped|opened/)             return "\033[36m"
                return "\033[90m"
            }
            function off() { return "\033[0m" }'
    fi
}

# Colour a unified diff on stdin. Prefers delta or bat when installed, since
# they do it better; falls back to awk so this never depends on either.
# Pipe the result to `less -R`, or the escapes render as text.
_g_colordiff() {
    if [ -n "${NO_COLOR:-}" ]; then
        cat
    elif command -v delta >/dev/null; then
        delta --paging=never
    elif command -v bat >/dev/null; then
        bat --language=diff --style=plain --color=always
    else
        awk '
            /^diff --git|^index /          { printf "\033[1;33m%s\033[0m\n", $0; next }
            /^\+\+\+|^---/              { printf "\033[1m%s\033[0m\n",    $0; next }
            /^@@/                          { printf "\033[36m%s\033[0m\n",   $0; next }
            /^\+/                         { printf "\033[32m%s\033[0m\n",   $0; next }
            /^-/                           { printf "\033[31m%s\033[0m\n",   $0; next }
                                           { print }
        '
    fi
}

# --- menu backends ----------------------------------------------------------
# Dynamic lists of unknown length -> fzf. Fixed short verb lists -> arrow menu.
# GLAB_MENU=menu forces the arrow menu everywhere.

# pick [fzf args...]   filter stdin, print the chosen line
pick() {
    if [ "${GLAB_MENU:-fzf}" = fzf ] && command -v fzf >/dev/null; then
        fzf "$@"
    else
        local items
        mapfile -t items
        menu_pick "select" "${items[@]}"
    fi
}

# menu_pick TITLE ITEM...   arrow-key menu; draws on the tty, answer on stdout
# Derived from Lifailon/Console-Menu (Apache 2.0), reshaped to return a value.
menu_pick() {
    local title=$1; shift
    local menu=("$@") selected=0 key i

    tput civis >/dev/tty
    while true; do
        {   clear
            printf '%s\n' "$title"
            for i in "${!menu[@]}"; do
                if [ "$i" -eq "$selected" ]; then
                    if [ -n "${NO_COLOR:-}" ]; then echo "> ${menu[$i]}"
                    else printf '\033[1;36m> %s\033[0m\n' "${menu[$i]}"; fi
                else
                    echo "  ${menu[$i]}"
                fi
            done
        } >/dev/tty

        IFS= read -rsn1 key </dev/tty
        # An arrow key is three bytes: ESC [ A. Swallow the first two.
        if [ "$key" = $'\e' ]; then
            read -rsn1 -t 0.01 key </dev/tty
            read -rsn1 -t 0.01 key </dev/tty
        fi

        case $key in
            "") break ;;
            A)  [ "$selected" -gt 0 ] && selected=$((selected - 1)) ;;
            B)  [ "$selected" -lt $(( ${#menu[@]} - 1 )) ] && selected=$((selected + 1)) ;;
            q)  tput cnorm >/dev/tty; clear >/dev/tty; return 1 ;;
        esac
    done
    tput cnorm >/dev/tty; clear >/dev/tty

    # Strip any colour before returning: the caller parses this string, and an
    # escape sequence in it would end up in an id or a key.
    printf '%s\n' "${menu[$selected]}" | sed 's/\x1b\[[0-9;]*m//g'
}

# --- auth -------------------------------------------------------------------

#: gauth [action]        check or fix GitLab authentication
#>   gauth                 status for every host glab knows about
#>   gauth login           interactive login for this repo's host
#>   gauth host            what host this repo resolves to, and is it GitLab
#>   gauth who             the account the current token belongs to
#>   gauth scopes          scopes and expiry of the token in use
#>   gauth rotate          rotate the current token (GitLab 16+, api scope)
#>
#>   the first token cannot be made locally - it is issued by the server,
#>   via the UI or via `gauth login` (OAuth device flow on gitlab.com).
#>   once you hold one with api scope, project tokens can be minted:
#>     glab api -X POST projects/:id/access_tokens \
#>       -f name=ci -f scopes[]=read_registry -f expires_at=2026-12-31
gauth() {
    command -v glab >/dev/null || { echo "glab not installed" >&2; return 1; }
    local host
    host=$(_g_host 2>/dev/null)

    case "${1:-status}" in
        status)
            glab auth status ;;
        host)
            [ -n "$host" ] || { echo "gauth: no remote here" >&2; return 1; }
            if _g_is_gitlab "$host"; then echo "$host  (GitLab)"
            else                          echo "$host  (not GitLab)"; return 1; fi ;;
        login)
            [ -n "$host" ] || { echo "gauth: no remote here" >&2; return 1; }
            if ! _g_is_gitlab "$host"; then
                echo "gauth: $host is not a GitLab instance - refusing to log in" >&2
                echo "       (this repo's origin points somewhere else)" >&2
                return 1
            fi
            glab auth login --hostname "$host" ;;
        who)
            glab api user | jq -r '"\(.username)  (\(.name))  id=\(.id)"' ;;
        scopes)
            glab api personal_access_tokens/self \
                | jq -r '"scopes:  \(.scopes | join(", "))\nexpires: \(.expires_at // "never")\nactive:  \(.active)"' ;;
        rotate)
            echo "rotating: the current token stops working immediately" >&2
            read -r -p "type yes to continue: " confirm
            [ "$confirm" = yes ] || { echo "cancelled" >&2; return 1; }
            glab api -X POST personal_access_tokens/self/rotate \
                | jq -r '"new token: \(.token)\nexpires:   \(.expires_at)"' ;;
        *)
            echo "gauth: unknown action '$1' (status host login who scopes rotate)" >&2
            return 1 ;;
    esac
}

# --- pipelines --------------------------------------------------------------

# One line per pipeline: id, status, ref, short sha, when. Fixed-width via awk
# rather than `column`, whose tab handling differs between util-linux and BSD.
# Field 1 is always the id, so ${line%% *} extracts it whatever follows.
_g_pipelines() {
    _g_api pipelines "?per_page=${1:-30}" \
        | jq -r '.[] | [.id, .status, .ref, (.sha[0:8]),
                        (.created_at[5:16] | sub("T"; " "))] | @tsv' \
        | awk -F'\t' "$(_g_colour_awk)"'
             { printf "%-10s %s%-9s%s %-30s %-9s %s\n",
                      $1, col($2), $2, off(), $3, $4, $5 }'
}

#: gpipe [n]             browse pipelines, drill into jobs
#>   gpipe                 last 20 pipelines
#>   gpipe 100             last 100
#>   enter on a pipeline opens its jobs; ctrl-v opens it in glab's own TUI
#>
#>   GLAB_MENU=menu gpipe  arrow keys instead of fzf everywhere
#>
#>   job logs are cached under ~/.cache/glab-trace so scrolling the preview
#>   does not hit the API on every keystroke; G_TRACE_TTL=30 seconds by
#>   default, set it to 0 to always refetch a running job
gpipe() {
    _g_ready || return 1

    local out key line id
    # Loop: coming back from a pipeline returns here rather than to the shell.
    # esc leaves for good.
    while true; do
        # --expect makes fzf print the pressed key as the first line, which is
        # how one picker offers two actions without a second menu.
        out=$(_g_pipelines "${1:-20}" | pick --ansi --prompt='pipeline> ' --height=60% \
                  --expect=ctrl-v \
                  --header='enter: jobs   ctrl-v: glab TUI   esc: quit') || return 0

        key=$(printf '%s\n' "$out" | sed -n 1p)
        line=$(printf '%s\n' "$out" | sed -n 2p)
        [ -n "$line" ] || line=$key        # arrow-menu backend returns one line
        [ -n "$line" ] || return 0

        id=${line%% *}
        if [ "$key" = ctrl-v ]; then
            glab ci view -p "$id"
        else
            gjob "$id"
        fi
    done
}

# --- jobs -------------------------------------------------------------------

# duration is null on jobs that never ran, hence the // 0 default.
_g_jobs() {
    _g_api "pipelines/$1/jobs" '?per_page=100' \
        | jq -r '.[] | [.id, .status, .stage, .name,
                        ((.duration // 0) | floor | tostring + "s")] | @tsv' \
        | awk -F'\t' "$(_g_colour_awk)"'
             { printf "%-10s %s%-9s%s %-12s %-28s %s\n",
                      $1, col($2), $2, off(), $3, $4, $5 }'
}

#: gjob [pipeline-id]    browse the jobs of a pipeline and act on one
#>   gjob                  jobs of the newest pipeline on the current branch
#>   gjob 123456           jobs of that pipeline
#>
#>   the preview pane tails the job log while you move through the list;
#>   enter opens an action menu: trace, retry, cancel, play, artifacts, browser
#>   after an action you return to the job list; esc goes back one level
gjob() {
    _g_ready || return 1

    local pid line jid proj action
    proj=$(_g_project) || return 1

    if [ -n "${1:-}" ]; then
        pid=$1
    else
        # newest pipeline on the branch you are standing on
        pid=$(_g_api pipelines "?ref=$(git branch --show-current)&per_page=1" \
              | jq -r '.[0].id // empty')
        [ -n "$pid" ] || { echo "gjob: no pipeline for this branch" >&2; return 1; }
    fi

    # Loop: after an action you land back on the job list. esc goes up one
    # level, to the pipeline list if gpipe called us, otherwise to the shell.
    while true; do
        line=$(_g_jobs "$pid" | pick --ansi --prompt='job> ' --height=70% \
                  --preview="g-trace $proj {1} 40" \
                  --preview-window=right:60%:wrap \
                  --header='enter: actions   esc: back') || return 0
        [ -n "$line" ] || return 0
        jid=${line%% *}

        # Fixed short verb list: the arrow menu suits this better than a filter.
        # Reuse the selected row as the header: it already shows status,
        # stage, name and duration.
        action=$(menu_pick "job $jid
  $line
" trace retry cancel play artifacts browser pipeline log back) \
            || continue                     # esc or q in the menu: back to jobs

        case $action in
            trace)     glab api "projects/$proj/jobs/$jid/trace" \
                           | g-clean | ${PAGER:-less} -R ;;
            retry)     glab api -X POST "projects/$proj/jobs/$jid/retry"  | jq -r '.id, .status' ;;
            cancel)    glab api -X POST "projects/$proj/jobs/$jid/cancel" | jq -r '.id, .status' ;;
            play)      glab api -X POST "projects/$proj/jobs/$jid/play"   | jq -r '.id, .status' ;;
            artifacts) gart "$jid" ;;
            browser)   glab api "projects/$proj/jobs/$jid" | jq -r .web_url | xargs -r xdg-open ;;
            pipeline)  glab ci view -p "$pid" ;;
            log)       gfail "$pid" ;;
            back)      continue ;;
        esac

        # A pager clears itself; everything else prints a line or two that
        # would vanish the moment the list redraws.
        case $action in
            trace|pipeline|back) ;;
            *) read -r -p "enter to return to the job list... " _ </dev/tty ;;
        esac
    done
}

# --- artifacts --------------------------------------------------------------

#: gart <job-id>         download and inspect a job's artifacts
#>   gart 987654           downloads to ./artifacts-987654/ and lists contents
#>
#>   nothing is extracted over your working tree: the zip lands in a new
#>   directory named after the job, so two downloads never collide
gart() {
    _g_ready || return 1
    local jid=$1 proj dir
    [ -n "$jid" ] || { echo "usage: gart <job-id>" >&2; return 1; }

    proj=$(_g_project) || return 1
    dir="artifacts-$jid"
    mkdir -p "$dir" || return 1

    glab api "projects/$proj/jobs/$jid/artifacts" > "$dir/artifacts.zip" || return 1
    if ! unzip -l "$dir/artifacts.zip" >/dev/null 2>&1; then
        echo "gart: job $jid has no artifacts" >&2
        rm -rf "$dir"
        return 1
    fi

    unzip -l "$dir/artifacts.zip"
    echo "saved: $dir/artifacts.zip   (unzip -d $dir to extract)"
}

# --- glab's own TUI ---------------------------------------------------------

#: gview [branch|id]     glab's built-in pipeline TUI
#>   gview                 current branch
#>   gview main            a named branch
#>   gview 123456          a pipeline id (all digits)
#>
#>   full-screen stage graph, arrows to move, enter for logs, r retry, c cancel.
#>   use this for "what is my branch doing right now"; use gpipe to search
#>   across pipelines, download artifacts, or read a cached log
gview() {
    _g_ready || return 1
    local arg=${1:-}
    if [ -z "$arg" ]; then
        glab ci view -b "$(git branch --show-current)"
    elif [[ $arg =~ ^[0-9]+$ ]]; then
        glab ci view -p "$arg"          # all digits: treat it as a pipeline id
    else
        glab ci view -b "$arg"
    fi
}

#: gwatch [seconds]      follow the current branch's pipeline until it ends
#>   gwatch                poll every 15s
#>   gwatch 5              poll every 5s
#>
#>   `glab ci status` already does this, and better if you want to watch:
#>   it shows every job live and lets you act on them. use that one.
#>
#>   gwatch exists for the other case - not watching. it prints only when
#>   the status changes, exits on a terminal state, and holds no terminal,
#>   so it composes:
#>     gwatch && notify-send "pipeline done" "$(gnow | head -2)"
#>     gwatch && qrun -a
gwatch() {
    _g_ready || return 1
    local delay=${1:-15} ref pid status last=

    ref=$(git branch --show-current)
    pid=$(_g_api pipelines "?ref=$ref&per_page=1" | jq -r '.[0].id // empty')
    [ -n "$pid" ] || { echo "gwatch: no pipeline for $ref" >&2; return 1; }

    echo "watching pipeline $pid on $ref (ctrl-c to stop)"
    while true; do
        status=$(_g_api "pipelines/$pid" | jq -r .status)
        if [ "$status" != "$last" ]; then
            printf '%s  %s\n' "$(date +%H:%M:%S)" "$status"
            last=$status
        fi
        case $status in
            success|failed|canceled|skipped|manual) return 0 ;;
        esac
        sleep "$delay"
    done
}

# --- one-shot status --------------------------------------------------------

#: gnow                  branch, pipeline and MR status in one screen
#>   gnow                  no menus, no keystrokes, nothing to dismiss
#>
#>   the three API calls run in parallel, so it costs one round trip
#>   rather than three. failing job names are listed; everything else is
#>   one line each
gnow() {
    _g_ready || return 1

    local proj branch tmp pid
    proj=$(_g_project) || return 1
    branch=$(git branch --show-current)
    [ -n "$branch" ] || { echo "detached HEAD" >&2; return 1; }

    tmp=$(mktemp -d) || return 1
    # A RETURN trap set inside a function fires when it returns, including on
    # an early return, so the temp dir cannot leak if this grows more exits.
    trap 'rm -rf "$tmp"' RETURN

    # Fire both lookups at once: neither depends on the other.
    glab api "projects/$proj/pipelines?ref=$branch&per_page=1" > "$tmp/pipe" 2>/dev/null &
    glab api "projects/$proj/merge_requests?source_branch=$branch&state=opened" > "$tmp/mr" 2>/dev/null &
    wait

    [ -n "${GLAB_PROJECT:-}" ] && printf 'target    %s  (grepo off to undo)\n' "$GLAB_PROJECT"
    printf 'branch    %s\n' "$branch"

    pid=$(jq -r '.[0].id // empty' "$tmp/pipe" 2>/dev/null)
    if [ -z "$pid" ]; then
        printf 'pipeline  none\n'
    else
        jq -r '.[0] | "pipeline  \(.id)  \(.status)  \(.created_at[5:16] | sub("T"; " "))"' "$tmp/pipe"
        # Only the failures are worth naming; a green pipeline needs no detail.
        glab api "projects/$proj/pipelines/$pid/jobs?per_page=100" 2>/dev/null \
            | jq -r '.[] | select(.status == "failed") | "          failed: \(.stage)/\(.name)"'
    fi

    if [ -z "$(jq -r '.[0].iid // empty' "$tmp/mr" 2>/dev/null)" ]; then
        printf 'mr        none\n'
    else
        jq -r '.[0] | "mr        !\(.iid)  \(.title)"' "$tmp/mr"
    fi
}

# --- other repos ------------------------------------------------------------

#: grepo [search|off]    point the g* commands at another repo
#>   grepo                 pick from every project you are a member of
#>   grepo ecu             filter the list first
#>   grepo off             back to the repo you are standing in
#>   grepo -               same as off
#>
#>   sets GLAB_PROJECT for this shell only. gpipe, gjob, gstats, gmine and
#>   gmr then act on that project instead of the git remote.
#>
#>   branch-dependent commands (gnow, gwatch, gmr create) still read the
#>   local branch, so they make little sense pointed elsewhere - use gpipe
#>   and gstats for other repos
grepo() {
    command -v glab >/dev/null || { echo "glab not installed" >&2; return 1; }
    command -v jq   >/dev/null || { echo "jq not installed" >&2; return 1; }

    case "${1:-}" in
        off|-)
            unset GLAB_PROJECT
            echo "back to the local remote: $(_g_project 2>/dev/null || echo none)"
            return 0 ;;
    esac

    local line chosen
    line=$(glab api "projects?membership=true&simple=true&per_page=100&order_by=last_activity_at&search=${1:-}" \
           | jq -r '.[] | [.path_with_namespace, .name] | @tsv' \
           | awk -F'\t' '{ printf "%-48s %s\n", $1, $2 }' \
           | pick --prompt='repo> ' --height=60% \
                  --header="enter: target it   esc: cancel   current: ${GLAB_PROJECT:-$(_g_project 2>/dev/null | sed 's/%2F/\//g')}") \
        || return 0

    [ -n "$line" ] || return 0
    chosen=${line%% *}
    export GLAB_PROJECT=$chosen
    echo "now targeting $GLAB_PROJECT  (grepo off to undo)"
}
