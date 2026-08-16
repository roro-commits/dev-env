#@ 60 failure records
# Pipeline failure records: what broke, why, and what fixed it.
#
# Two registers, deliberately separate:
#   index.tsv       one line per failure, for counting and sorting
#   PF-YYYY-NNN.md  one file per failure, for the parts that need prose -
#                   the trace, the root cause, the fix, the diff that fixed it
#
# Capture happens when it breaks (what). Resolution happens when it passes
# (why, how). Writing both at failure time produces guesses.

GFAIL_DIR="${GFAIL_DIR:-$HOME/Documents/pipeline-failures}"
GFAIL_INDEX="${GFAIL_INDEX:-$GFAIL_DIR/index.tsv}"

# --- internal ---------------------------------------------------------------

# Next PF-YYYY-NNN for the current year.
_gfail_next_id() {
    local year max=0 n id
    year=$(date +%Y)
    if [ -f "$GFAIL_INDEX" ]; then
        while IFS=$'\t' read -r id _; do
            case $id in
                PF-"$year"-*) n=$((10#${id##*-})); [ "$n" -gt "$max" ] && max=$n ;;
            esac
        done < "$GFAIL_INDEX"
    fi
    printf 'PF-%s-%03d\n' "$year" "$((max + 1))"
}

# Guess a category from the failed jobs. Correcting a guess beats choosing cold.
# Matched case-insensitively, since stage names vary: linting/hadoLint,
# Lint, LINT. Only a starting point - fzf lets you type anything.
_gfail_guess() {
    local j
    j=$(tr '[:upper:]' '[:lower:]' <<< "$1")
    case "$j" in
        *lint*|*format*|*whitespace*|*style*|*pre-commit*) echo lint ;;
        *test*|*spec*)                                     echo test ;;
        *build*|*compile*|*docker*|*kaniko*)               echo build ;;
        *deploy*|*release*|*publish*)                      echo deploy ;;
        *sign*|*scan*|*trivy*)                             echo security ;;
        *)                                                 echo other ;;
    esac
}

# Categories: the built-in set plus every one already used, so the list grows
# with the project instead of being fixed by me.
_gfail_categories() {
    {   printf '%s\n' lint format test flaky config dep infra real
        [ -f "$GFAIL_INDEX" ] && cut -f6 "$GFAIL_INDEX"
    } | grep -v '^[[:space:]]*$' | sort -u
}

# The exit code is a pattern worth keeping - 127 missing binary, 137 OOM,
# 143 cancelled, 1 the tool itself said no. Pulled separately from the cause.
# Common exit codes, so the number means something at a glance.
_gfail_exitmeaning() {
    case "${1:-}" in
        1)   echo "  (the tool said no)" ;;
        2)   echo "  (usage or syntax)" ;;
        126) echo "  (found but not executable)" ;;
        127) echo "  (command not found)" ;;
        137) echo "  (SIGKILL - usually OOM)" ;;
        139) echo "  (SIGSEGV)" ;;
        143) echo "  (SIGTERM - cancelled or timed out)" ;;
        *)   echo "" ;;
    esac
}

_gfail_exitcode() {
    grep -oE 'exit code [0-9]+' | tail -1 | grep -oE '[0-9]+'
}

# "ERROR: Job failed: exit code 127" is never the useful line - the cause is
# above it. Pull the lines that look like a real error instead of just the last.
_gfail_errlines() {
    grep -iE 'error|failed|failure|not found|no such|denied|cannot|refused|exception|traceback|undefined' \
        | grep -viE '^[[:space:]]*$|Job failed: exit code|ERROR: Job failed' \
        | tail -3
}

# Fetch a pipeline, or fail loudly. A bad id makes glab print a 404 and hand
# jq a string, which otherwise flows on into an empty, useless record.
_g_pipeline_or_die() {
    local out
    out=$(_g_api "pipelines/$1" 2>/dev/null)
    if ! jq -e 'type == "object" and has("id")' >/dev/null 2>&1 <<< "$out"; then
        echo "gfail: no pipeline $1 in this project" >&2
        return 1
    fi
    printf '%s\n' "$out"
}

_gfail_file() { printf '%s/%s.md\n' "$GFAIL_DIR" "$1"; }

_gfail_row() {
    [ -f "$GFAIL_INDEX" ] && awk -F'\t' -v id="$1" '$1 == id' "$GFAIL_INDEX"
}

# --- commands ---------------------------------------------------------------

#: gfail [action]        record why a pipeline failed and what fixed it
#>   gfail                 capture the current branch's failed pipeline
#>   gfail 123456          capture a specific pipeline
#>   gfail pick [n]        choose from recent failures on any branch
#>   gfail fix             close the newest open record with the diff that fixed it
#>   gfail fix PF-2026-004 close a specific one
#>   gfail list [n]        recent records
#>   gfail open [id]       open a record in $EDITOR (newest if no id)
#>   gfail stats           counts and time cost, by category
#>   gfail find <text>     search every record, preview the match
#>   gfail grep <text>     plain grep, one line per hit, pipeable
#>
#>   capture writes what broke: failed jobs, duration, and the tail of the
#>   trace. fix writes why and how: it diffs the failing commit against the
#>   one that passed, inlining the diff or linking to it when it is large.
#>
#>   records live in ~/Documents/pipeline-failures - set GFAIL_DIR to move
#>   them. one markdown file each, plus index.tsv for counting.
gfail() {
    case "${1:-capture}" in
        fix|f)   shift; _gfail_fix "${1:-}" ;;
        list|l)  shift; _gfail_list "${1:-20}" ;;
        open|o)  shift; _gfail_open "${1:-}" ;;
        pick|p)  shift; _gfail_pick "${1:-20}" ;;
        stats|s) _gfail_stats ;;
        find)    shift; _gfail_find "$*" ;;
        grep|g)  shift; _gfail_grep "$*" ;;
        *)       _gfail_capture "${1:-}" ;;
    esac
}

# Plain `gfail` only reaches the newest failure on the current branch. This
# reaches any of them, on any branch, including ones you walked past earlier.
_gfail_pick() {
    _g_ready || return 1

    local line pid proj
    proj=$(_g_project) || return 1

    # Loops like the other pickers: recording one failure returns you to the
    # list, esc leaves. The preview shows the failing job log, so you know
    # what you are picking before committing to write it up.
    while true; do
        line=$(_g_api pipelines "?status=failed&per_page=${1:-20}" \
               | jq -r '.[] | [.id, .ref, (.created_at[5:16] | sub("T"; " "))] | @tsv' \
               | awk -F'\t' '{ printf "%-11s %-24s %s\n", $1, $2, $3 }' \
               | pick --prompt='failure> ' --height=70% \
                      --preview="g-ptrace $proj {1} 30" \
                      --preview-window=right:55%:wrap \
                      --header='enter: record it   esc: back') || return 0

        [ -n "$line" ] || return 0
        pid=${line%% *}
        _gfail_capture "$pid"
    done
}

_gfail_capture() {
    _g_ready || return 1

    local pid proj branch jobs dur sha guess category cause id file weburl
    local firstjob pipe jobsjson answer trace exitcode=

    proj=$(_g_project) || return 1
    branch=$(git branch --show-current)

    if [ -n "${1:-}" ] && [ "$1" != capture ]; then
        pid=$1
    else
        pid=$(_g_api pipelines "?ref=$branch&status=failed&per_page=1" \
              | jq -r '.[0].id // empty')
        [ -n "$pid" ] || { echo "gfail: no failed pipeline on $branch" >&2; return 1; }
    fi

    pipe=$(_g_pipeline_or_die "$pid") || return 1
    jobsjson=$(_g_api "pipelines/$pid/jobs" '?per_page=100' 2>/dev/null)

    dur=$(jq -r '.duration // 0' <<< "$pipe")
    sha=$(jq -r '.sha' <<< "$pipe")
    weburl=$(jq -r '.web_url' <<< "$pipe")
    jobs=$(jq -r '[.[] | select(.status == "failed")
                  | "\(.stage)/\(.name)"] | join(",")' <<< "$jobsjson")
    firstjob=$(jq -r '[.[] | select(.status == "failed")][0].id // empty' <<< "$jobsjson")
    [ -n "$jobs" ] || jobs="(none)"

    echo "pipeline $pid on $branch"
    echo "failed:  $jobs"

    # Fetch the trace once, show it, then ask. Asking first meant summarising
    # an error you had not been shown.
    trace=
    if [ -n "$firstjob" ]; then
        trace=$(glab api "projects/$proj/jobs/$firstjob/trace" 2>/dev/null | g-clean)
    fi

    if [ -n "$trace" ]; then
        printf '\n--- tail of %s ---\n' "${jobs%%,*}"
        tail -25 <<< "$trace"
        local errlines
        errlines=$(_gfail_errlines <<< "$trace")
        exitcode=$(_gfail_exitcode <<< "$trace")
        if [ -n "$errlines" ]; then
            printf -- '--- likely cause ---\n%s\n' "$errlines"
        fi
        [ -n "$exitcode" ] && printf -- '--- exit code %s%s ---\n' \
            "$exitcode" "$(_gfail_exitmeaning "$exitcode")"
        printf '\n'
    else
        printf '\n(no trace available)\n\n'
    fi

    guess=$(_gfail_guess "$jobs")

    # fzf with --height renders inline, so the trace printed above stays on
    # screen while you choose. --print-query means typing a category that does
    # not exist yet creates it: the vocabulary is yours, not mine.
    category=$(_gfail_categories \
        | fzf --prompt='category> ' --height=40% --query="$guess" \
              --print-query --header='enter: choose   type a new one to add it' \
        | tail -1)
    [ -n "$category" ] || { echo "gfail: no category" >&2; return 1; }

    read -r -e -p "cause (what the tool objected to), one line: " cause </dev/tty
    cause=${cause//$'\t'/ }

    id=$(_gfail_next_id)
    file=$(_gfail_file "$id")
    mkdir -p "$GFAIL_DIR" || return 1

    # shellcheck disable=SC2016   # backticks below are markdown, not substitution
    {
        printf '# %s  %s\n\n' "$id" "$cause"
        printf '| field | value |\n|---|---|\n'
        printf '| date | %s |\n'          "$(date +%F)"
        printf '| project | %s |\n'       "${proj//%2F//}"
        printf '| branch | %s |\n'        "$branch"
        printf '| pipeline | [%s](%s) |\n' "$pid" "$weburl"
        printf '| commit | `%s` |\n'      "$sha"
        printf '| duration | %ss |\n'     "$dur"
        printf '| category | %s |\n'      "$category"
        printf '| failed jobs | %s |\n'   "$jobs"
        printf '| exit code | %s%s |\n'   "${exitcode:-?}" "$(_gfail_exitmeaning "$exitcode")"
        printf '| status | open |\n\n'

        printf '## What failed\n\n```\n'
        if [ -n "$trace" ]; then
            tail -30 <<< "$trace"
        else
            echo "(no trace)"
        fi
        printf '```\n\n'

        printf '## Cause\n\n%s\n\n' "$cause"
        printf '_The proximate thing: what the tool objected to._\n\n'

        printf '## Root cause\n\n'
        printf '_Why the mistake was possible at all. Not the error - the gap\n'
        printf 'that let it through. Did I not know the rule, was the hook not\n'
        printf 'installed, was the example I copied wrong, was the check running\n'
        printf 'too late to help? Keep asking why until the answer is about a\n'
        printf 'process rather than a keystroke._\n\n'

        printf '## Fix\n\n'
        printf '_Two parts: what I changed to make it pass, and what would stop\n'
        printf 'this whole class of failure happening again. If the second is\n'
        printf 'empty, the root cause above is probably still a symptom._\n\n'

        printf '## Resolved by\n\n_filled in by `gfail fix`_\n'
    } > "$file"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$(date +%F)" "${proj//%2F//}" "$pid" "$branch" \
        "$category" "$dur" "$jobs" open "$cause" "${exitcode:-}" >> "$GFAIL_INDEX"

    echo "$id  ->  $file"
    read -r -p "open it now? [y/N] " answer </dev/tty
    [ "$answer" = y ] && ${EDITOR:-hx} "$file"
    return 0
}

_gfail_fix() {
    _g_ready || return 1

    local id row file proj branch failpid failsha failat
    local passing passsha passpid passurl lines projurl mrs commits

    proj=$(_g_project) || return 1

    if [ -n "${1:-}" ]; then
        id=$1
    else
        id=$(awk -F'\t' '$9 == "open" { last = $1 } END { print last }' \
             "$GFAIL_INDEX" 2>/dev/null)
        [ -n "$id" ] || { echo "gfail: no open records" >&2; return 1; }
    fi

    row=$(_gfail_row "$id")
    [ -n "$row" ] || { echo "gfail: no record $id" >&2; return 1; }

    failpid=$(cut -f4 <<< "$row")
    branch=$(cut -f5 <<< "$row")
    file=$(_gfail_file "$id")

    # Re-read the failure from the API rather than parsing our own markdown:
    # we need its timestamp, and one call is cheaper than a fragile grep.
    local failpipe
    failpipe=$(_g_pipeline_or_die "$failpid") || return 1
    failsha=$(jq -r .sha        <<< "$failpipe")
    failat=$( jq -r .created_at <<< "$failpipe")

    # The FIRST success after the failure, not the newest. The newest could be
    # twenty commits later, which would drag unrelated work into the diff.
    passing=$(_g_api pipelines "?ref=$branch&status=success&per_page=100" \
              | jq -r --arg t "$failat" '
                    [.[] | select(.created_at > $t)]
                    | sort_by(.created_at) | .[0] // empty')

    [ -n "$passing" ] || {
        echo "gfail: no successful pipeline on $branch after $failat" >&2; return 1; }

    passsha=$(jq -r .sha     <<< "$passing")
    passpid=$(jq -r .id      <<< "$passing")
    passurl=$(jq -r .web_url <<< "$passing")

    # Any MR carrying this branch, merged or not.
    mrs=$(_g_api merge_requests "?source_branch=$branch&per_page=5" \
          | jq -r '.[] | "!\(.iid) \(.state) \(.web_url) \(.merge_commit_sha // "-")"')

    lines=$(git diff --numstat "$failsha" "$passsha" 2>/dev/null \
            | awk '{ a += $1; d += $2 } END { print a + d + 0 }')
    lines=${lines:-0}
    commits=$(git log --oneline "$failsha..$passsha" 2>/dev/null)

    # shellcheck disable=SC2016   # markdown backticks
    {
        printf '\nFirst pipeline to pass after this failure:\n\n'
        printf '- pipeline [%s](%s) on `%s`\n' "$passpid" "$passurl" "$passsha"

        if [ -n "$mrs" ]; then
            printf '\nMerge requests on this branch:\n\n'
            while read -r iid state url mergesha; do
                if [ "$mergesha" = "-" ]; then
                    printf '- %s (%s) %s\n' "$iid" "$state" "$url"
                else
                    printf '- %s (%s) %s - merged as `%s`\n' \
                        "$iid" "$state" "$url" "$mergesha"
                fi
            done <<< "$mrs"
        fi

        printf '\n### Candidate change set\n\n'
        printf '_Everything between the failing and passing commit. The fix is\n'
        printf 'in here somewhere; unrelated commits may be too._\n\n'

        if [ -n "$commits" ]; then
            printf '```\n%s\n```\n\n' "$commits"
        fi

        if [ "$lines" -gt 0 ] && [ "$lines" -le 80 ]; then
            printf '```diff\n'
            git diff "$failsha" "$passsha"
            printf '```\n'
        else
            projurl=$(_g_api "" | jq -r .web_url)
            printf '%s changed lines - [compare view](%s/-/compare/%s...%s)\n' \
                "$lines" "$projurl" "$failsha" "$passsha"
        fi
    } >> "$file"

    awk -F'\t' -v OFS='\t' -v id="$id" '$1 == id { $9 = "fixed" } { print }' \
        "$GFAIL_INDEX" > "$GFAIL_INDEX.tmp" && mv "$GFAIL_INDEX.tmp" "$GFAIL_INDEX"

    echo "$id closed. Narrow the candidate set to the actual cause while you"
    echo "still remember which commit it was."
    ${EDITOR:-hx} "$file"
}

_gfail_list() {
    [ -f "$GFAIL_INDEX" ] || { echo "no records yet"; return 0; }
    tail -n "$1" "$GFAIL_INDEX" \
        | awk -F'\t' '{ printf "%-12s %s  %-7s %-6s %5ss  %-16s %s\n",
                        $1, $2, $6, $9, $7, $5, $10 }'
}

_gfail_open() {
    local id=${1:-}
    [ -f "$GFAIL_INDEX" ] || { echo "no records yet"; return 0; }
    [ -n "$id" ] || id=$(awk -F'\t' 'END { print $1 }' "$GFAIL_INDEX")
    ${EDITOR:-hx} "$(_gfail_file "$id")"
}

# Interactive search across the whole corpus. Every line of every record
# becomes a candidate, so fzf fuzzy-matches the trace text and the diff, not
# just the summary - six months from now you will remember the error string,
# not your own wording of it. Blank lines and code fences are dropped as noise.
_gfail_find() {
    local hit id
    [ -d "$GFAIL_DIR" ] || { echo "no records yet"; return 0; }

    # Loops like every other picker here: closing the editor puts you back on
    # the search, esc leaves.
    while true; do
        hit=$(grep -rn --include='*.md' -v -e '^[[:space:]]*$' -e '^```' \
                    -e '^## ' -e '^|---' "$GFAIL_DIR" 2>/dev/null \
              | sed "s|^$GFAIL_DIR/||; s|\.md:| |; s|:| |" \
              | pick --prompt='search> ' --height=70% \
                     --query="${1:-}" \
                     --preview="cat $GFAIL_DIR/{1}.md" \
                     --preview-window=right:60%:wrap \
                     --header='enter: open   esc: back') || return 0

        [ -n "$hit" ] || return 0
        id=${hit%% *}
        ${EDITOR:-hx} "$(_gfail_file "$id")"
    done
}

# Non-interactive: one line per match, so it composes with everything else.
_gfail_grep() {
    [ -d "$GFAIL_DIR" ] || { echo "no records yet"; return 0; }
    grep -rin --include='*.md' -- "$1" "$GFAIL_DIR" \
        | sed "s|^$GFAIL_DIR/||"
}

_gfail_stats() {
    [ -f "$GFAIL_INDEX" ] || { echo "no records yet"; return 0; }

    echo "by category, with the time each cost"
    awk -F'\t' '
        { n[$6]++; secs[$6] += $7 }
        END { for (c in n)
                printf "  %-9s %3d   %dm%02ds\n", c, n[c], secs[c] / 60, secs[c] % 60 }' \
        "$GFAIL_INDEX" | sort -k2 -rn

    echo
    echo "by exit code"
    awk -F'\t' '$11 != "" { n[$11]++ }
        END { for (c in n) printf "  %-6s %d\n", c, n[c] }' "$GFAIL_INDEX" | sort -k2 -rn

    echo
    awk -F'\t' '
        { total++; secs += $7; if ($9 == "open") open++
          if ($6 == "lint" || $6 == "format") { p++; psecs += $7 } }
        END {
            printf "  %d records, %d still open\n", total, open + 0
            printf "  %dm%02ds lost to failed pipelines\n", secs / 60, secs % 60
            printf "  %d preventable locally, costing %dm%02ds\n",
                   p + 0, psecs / 60, psecs % 60
        }' "$GFAIL_INDEX"
}

# --- other people's failures ------------------------------------------------

#: gmine [n]             fail->pass pairs across the whole project, not just yours
#>   gmine                 scan the last 200 pipelines
#>   gmine 500             go further back
#>
#>   the API is scoped to the project, so this covers everyone's branches.
#>   for each failed pipeline it finds the next success on the same ref and
#>   pairs them: the error, and the change that made it go away.
#>
#>   this is committed history, visible to anyone with repo access - it is
#>   reading the record, not watching people. keep notes about failure
#>   modes, not about who caused them.
#>
#>   enter saves it as a record   ctrl-o opens the diff   ctrl-b does both
#>
#>   records go to the same place as your own, ~/Documents/pipeline-failures,
#>   with status "noted" rather than "open" - it is not your failure to fix,
#>   so it never counts as work you owe. gfail find searches both.
gmine() {
    _g_ready || return 1

    local n=${1:-200} proj projurl pairs choice failsha passsha url
    proj=$(_g_project) || return 1
    projurl=$(_g_api "" | jq -r .web_url)

    # Within each ref, ordered by time, a failure immediately followed by a
    # success is a fix. Consecutive failures and abandoned branches drop out.
    pairs=$(_g_api pipelines "?per_page=$n" \
        | jq -r '
            group_by(.ref)
            | map(sort_by(.created_at)
                  | . as $g
                  | [range(0; length - 1)]
                  | map(select($g[.].status == "failed" and $g[.+1].status == "success")
                        | { ref: $g[.].ref,
                            failed: $g[.].id,   failsha: $g[.].sha,
                            passed: $g[.+1].id, passsha: $g[.+1].sha,
                            when: $g[.].created_at[5:16] }))
            | flatten
            | sort_by(.when) | reverse
            | .[]
            | [ "\(.when)  \(.ref)  \(.failed) -> \(.passed)",
                .failed, .failsha, .passsha ] | @tsv')

    [ -n "$pairs" ] || { echo "gmine: no fail->pass pairs in the last $n pipelines"; return 0; }

    # Field 1 is displayed; 2-4 stay hidden but reachable in preview and output.
    # One keypress decides what happens: no action menu in the way.
    local key failpid
    while true; do
        choice=$(printf '%s\n' "$pairs" \
        | pick --prompt='fix> ' --height=70% \
               --delimiter='\t' --with-nth=1 \
               --expect=ctrl-o,ctrl-b \
               --preview="g-ptrace $proj {2} 30" \
               --preview-window=right:55%:wrap \
               --header='enter: save   ctrl-o: diff   ctrl-b: both   esc: quit') \
        || return 0

        key=$(sed -n 1p <<< "$choice")
        choice=$(sed -n 2p <<< "$choice")
        [ -n "$choice" ] || return 0

        failpid=$(cut -f2 <<< "$choice")
        failsha=$(cut -f3 <<< "$choice")
        passsha=$(cut -f4 <<< "$choice")
        url="$projurl/-/compare/$failsha...$passsha"

        case $key in
        ctrl-o|ctrl-b)
            echo "$url"
            command -v xdg-open >/dev/null && xdg-open "$url" 2>/dev/null ;;
        esac

        case $key in
        ctrl-o) ;;                                    # diff only
        *)      _gmine_save "$failpid" "$failsha" "$passsha" "$url" ;;
        esac
    done
}

# Someone else's failure, kept because the failure mode is what matters. Status
# is "noted" rather than open: it is not yours to fix, so it never shows up in
# board's open count or as work you owe.
_gmine_save() {
    local failpid=$1 failsha=$2 passsha=$3 url=$4
    local proj jobsjson jobs firstjob trace exitcode category note id file pipe ref dur

    proj=$(_g_project) || return 1
    pipe=$(_g_pipeline_or_die "$failpid") || return 1
    ref=$(jq -r .ref <<< "$pipe")
    dur=$(jq -r '.duration // 0' <<< "$pipe")

    jobsjson=$(_g_api "pipelines/$failpid/jobs" '?per_page=100' 2>/dev/null)
    jobs=$(jq -r '[.[] | select(.status == "failed")
                  | "\(.stage)/\(.name)"] | join(",")' <<< "$jobsjson")
    firstjob=$(jq -r '[.[] | select(.status == "failed")][0].id // empty' <<< "$jobsjson")

    trace=
    [ -n "$firstjob" ] && trace=$(glab api "projects/$proj/jobs/$firstjob/trace" 2>/dev/null | g-clean)
    exitcode=$(_gfail_exitcode <<< "$trace")

    printf '\n--- likely cause ---\n%s\n\n' "$(_gfail_errlines <<< "$trace")"

    category=$(_gfail_categories \
        | fzf --prompt='category> ' --height=40% \
              --query="$(_gfail_guess "$jobs")" --print-query \
              --header='enter: choose   type a new one to add it' | tail -1) || return 1
    [ -n "$category" ] || return 1

    read -r -e -p "cause (what the tool objected to), one line: " note </dev/tty
    note=${note//$'\t'/ }

    id=$(_gfail_next_id)
    file=$(_gfail_file "$id")
    mkdir -p "$GFAIL_DIR" || return 1

    # shellcheck disable=SC2016   # markdown backticks
    {
        printf '# %s  %s\n\n' "$id" "$note"
        printf '_Observed on %s, not my pipeline._\n\n' "$ref"
        printf '| field | value |\n|---|---|\n'
        printf '| date | %s |\n'        "$(date +%F)"
        printf '| project | %s |\n'     "${proj//%2F//}"
        printf '| ref | %s |\n'         "$ref"
        printf '| pipeline | %s |\n'    "$failpid"
        printf '| duration | %ss |\n'   "$dur"
        printf '| category | %s |\n'    "$category"
        printf '| failed jobs | %s |\n' "$jobs"
        printf '| exit code | %s%s |\n' "${exitcode:-?}" "$(_gfail_exitmeaning "$exitcode")"
        printf '| status | noted |\n\n'

        printf '## What failed\n\n```\n'
        if [ -n "$trace" ]; then tail -30 <<< "$trace"; else echo "(no trace)"; fi
        printf '```\n\n'

        printf '## Cause\n\n%s\n\n' "$note"

        printf '## Root cause\n\n'
        printf '_Inferred, not known - it was not my failure. What gap made it\n'
        printf 'possible? If the same gap exists in my pipelines, that is the\n'
        printf 'only part of this record that matters._\n\n'

        printf '## Fix\n\n'
        printf -- '- [compare view](%s)\n' "$url"
        printf -- '- `%s` -> `%s`\n\n' "$failsha" "$passsha"
        printf '_Candidate change set: the fix is in there, and so may be\n'
        printf 'unrelated commits._\n\n'

        printf '## Does this apply to me\n\n_the transferable part_\n'
    } > "$file"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$id" "$(date +%F)" "${proj//%2F//}" "$failpid" "$ref" \
        "$category" "$dur" "$jobs" noted "$note" "${exitcode:-}" >> "$GFAIL_INDEX"

    echo "$id  ->  $file"
}

# --- measured, not logged ---------------------------------------------------

#: gstats [n] [ref]      real pipeline numbers from the API, nothing to log
#>   gstats                last 100 pipelines
#>   gstats 500            further back
#>   gstats 100 main       one branch only
#>
#>   works retroactively - last month's failures are already measured.
#>   watch mean-time-to-fail against mean-time-to-pass: if failures take as
#>   long as successes, the cheap checks are running too late in the pipeline
gstats() {
    _g_ready || return 1

    local n=${1:-100} ref=${2:-} query
    query="?per_page=$n"
    [ -n "$ref" ] && query="$query&ref=$ref"

    _g_api pipelines "$query" \
        | jq -r '.[] | [.status, (.duration // 0), .created_at[0:10]] | @tsv' \
        | awk -F'\t' '
            function hms(s,   h, m) {
                h = int(s / 3600); m = int((s % 3600) / 60)
                return (h > 0) ? sprintf("%dh%02dm", h, m) : sprintf("%dm%02ds", m, s % 60)
            }
            {
                total++; n[$1]++; secs[$1] += $2
                month[substr($3, 1, 7)]++
                if ($1 == "failed") failmonth[substr($3, 1, 7)]++
            }
            END {
                if (total == 0) { print "no pipelines"; exit }

                printf "%d pipelines\n\n", total
                for (s in n)
                    printf "  %-10s %4d   %5.1f%%   %s total\n",
                           s, n[s], 100 * n[s] / total, hms(secs[s])

                printf "\n  success rate        %.0f%%\n", 100 * (n["success"] + 0) / total
                printf "  time inside failed  %s\n", hms(secs["failed"] + 0)
                if (n["failed"] > 0)
                    printf "  mean time to fail   %s\n", hms(secs["failed"] / n["failed"])
                if (n["success"] > 0)
                    printf "  mean time to pass   %s\n", hms(secs["success"] / n["success"])

                printf "\n  by month\n"
                for (mo in month)
                    printf "    %s   %3d runs   %3d failed\n",
                           mo, month[mo], failmonth[mo] + 0
            }'
}

# --- exit codes -------------------------------------------------------------

#: gcode [n]             what an exit code means, and how often you have hit it
#>   gcode                 the common ones, with your own counts beside them
#>   gcode 127             explain one
#>
#>   these are the shell's, not GitLab's - the exit status of whatever
#>   command ran. above 128 means killed by signal n-128.
#>     man bash    the EXIT STATUS section
#>     kill -l     signal numbers
#>     man sysexits  the BSD 64-78 conventions some tools follow
#>
#>   GitLab records its own failure_reason on the job (script_failure,
#>   runner_system_failure, job_execution_timeout) - a different field
gcode() {
    local codes n meaning count

    codes="0|success
1|the tool said no - the usual lint or test failure
2|usage or syntax error in how it was invoked
126|found but not executable - missing +x, or a directory
127|command not found - missing from the image, or a typo, or PATH
128|invalid argument to exit
130|SIGINT - ctrl-c
137|SIGKILL - almost always the OOM killer
139|SIGSEGV - segfault
143|SIGTERM - cancelled, or a job timeout"

    # 64-78 are the BSD sysexits conventions, followed by some tools and
    # ignored by most. man sysexits.
    local sysexits="64|usage
65|input data was wrong
66|input file missing or unreadable
67|no such user
68|no such host
69|a service it needed was unavailable
70|internal software error
71|OS error
72|a system file was missing or bad
73|could not create an output file
74|I/O error
75|temporary failure - retrying may work
76|protocol error
77|permission denied
78|configuration error"

    if [ -n "${1:-}" ]; then
        meaning=$(grep "^$1|" <<< "$codes" | cut -d'|' -f2)

        if [ -z "$meaning" ]; then
            meaning=$(grep "^$1|" <<< "$sysexits" | cut -d'|' -f2)
            [ -n "$meaning" ] && meaning="$meaning  (if the tool follows sysexits)"
        fi

        # Valid signals are 1-64, so only 129-192 are really signal deaths.
        if [ -z "$meaning" ] && [ "$1" -gt 128 ] && [ "$1" -le 192 ] 2>/dev/null; then
            meaning="killed by signal $(( $1 - 128 ))  ($(kill -l "$(( $1 - 128 ))" 2>/dev/null))"
        fi

        if [ -z "$meaning" ]; then
            # Everything from 3 to 63 is whatever the program decided it means.
            # There is no registry; the tool that exited is the only authority.
            printf '%s  no standard meaning - defined by whatever command ran\n' "$1"
            printf '     look in the docs or man page for the command that ran\n'
            printf '     the trace line above the failure names it\n'
            return 0
        fi

        printf '%s  %s\n' "$1" "$meaning"
        return 0
    fi

    while IFS='|' read -r n meaning; do
        count=$(awk -F'\t' -v c="$n" '$11 == c { k++ } END { print k + 0 }' \
                "${GFAIL_INDEX:-/nonexistent}" 2>/dev/null)
        if [ "${count:-0}" -gt 0 ]; then
            printf '  %-4s %-52s  seen %s\n' "$n" "$meaning" "$count"
        else
            printf '  %-4s %s\n' "$n" "$meaning"
        fi
    done <<< "$codes"

    printf '\n  3-63     no standard meaning - whatever the command decided\n'
    printf '  64-78    BSD sysexits, if the tool follows them (man sysexits)\n'
    printf '  129+     killed by signal n-128 (kill -l)\n'
}
