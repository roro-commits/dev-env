#@ 45 gitlab - merge requests
# Merge requests. glab already does the work; this collects the choices.

# Names of templates in .gitlab/merge_request_templates/, without .md
_g_templates() {
    local d=.gitlab/merge_request_templates f
    [ -d "$d" ] || return 0
    for f in "$d"/*.md; do
        [ -e "$f" ] || continue
        basename "$f" .md
    done
}

_g_default_branch() {
    _g_api "" | jq -r '.default_branch // "main"'
}

#: gmr [action]          merge requests - the hub view
#>   gmr                   browse open MRs and act on one
#>   gmr mine              only the ones you opened
#>   gmr new               create one from the current branch
#>   gmr view              the MR for the current branch
#>
#>   this is the view worth defaulting to: each row carries its pipeline
#>   status, and from a row you can reach the jobs, the trace, the diff,
#>   the comments and the merge - everything else links off it
#>
#>   the list shows pipeline status and when the MR was last updated, so you
#>   can see what passed and what is stale without opening anything
#>
#>   the action menu has: pipeline, view, diff, comments, comment, assign,
#>   approve, checkout, browser, merge. pipeline drops you into that MR's
#>   job list; assign picks from the project's members.
#>   comments hides GitLab's own event entries ("changed title", "assigned
#>   to") and shows only real discussion
#>
#>   before asking anything it checks the branch has commits ahead of the
#>   target and that no open MR exists for it - both are failures glab only
#>   reports after it has already pushed
#>
#>   creating asks six things, each with a sane default:
#>     title      prefilled from the last commit subject, editable in place
#>     template   picked from .gitlab/merge_request_templates/ if any exist
#>     target     the project's default branch
#>     draft      no
#>     assignee   picked from project members, or none
#>     reviewer   picked from project members, or none
#>   it then prints the exact glab command and asks before running it
gmr() {
    _g_ready || return 1

    # Default is the list, not create: reading is safe, creating pushes a
    # branch. The safe thing should be the thing you get by reflex.
    case "${1:-list}" in
        list|l)     _gmr_list "" ;;
        mine|m)     _gmr_list mine ;;
        new|create) _gmr_create ;;
        view|v)     glab mr view ;;
        *) echo "gmr: unknown action '$1' (list mine new view)" >&2; return 1 ;;
    esac
}

# glab saves answers from a failed `mr create` under its config dir, keyed by
# the project path. A stale one is silently reused by --recover, so offer to
# deal with it up front rather than letting it resurface later.
# Users with access to this project. id first so field 1 is the id, which is
# what the API wants, while you search by the username you actually know.
_g_members() {
    _g_api users '?per_page=100' \
        | jq -r '.[] | [.id, .username, .name] | @tsv' \
        | awk -F'\t' '{ printf "%-8s %-20s %s\n", $1, $2, $3 }'
}

# Pick one member. Prints "id username", empty if none chosen.
_g_pick_member() {
    local line
    line=$( { echo "-        (none)"; _g_members; } \
            | pick --prompt="${1:-user}> " --height=40%) || return 1
    case $line in
        -*) return 0 ;;
    esac
    printf '%s %s\n' "$(echo "$line" | awk '{print $1}')" "$(echo "$line" | awk '{print $2}')"
}

_gmr_recover_file() {
    local proj
    proj=$(_g_project) || return 1
    printf '%s/glab-cli/recover/%s/mr.json\n' \
        "${XDG_CONFIG_HOME:-$HOME/.config}" "${proj//%2F//}"
}

_gmr_create() {
    local branch title target tmpl draft answer templates cmd

    local rec choice
    rec=$(_gmr_recover_file)
    if [ -f "$rec" ]; then
        echo "a saved attempt exists from a previous failure:"
        jq -r '"  title:  \(.title // "?")\n  target: \(.targetBranch // .target_branch // "?")"' \
            "$rec" 2>/dev/null || echo "  (unreadable)"
        choice=$(menu_pick "previous attempt" "retry it" "discard it" "ignore and start fresh") \
            || return 1
        case $choice in
            "retry it")   glab mr create --recover; return $? ;;
            "discard it") rm -f "$rec"; echo "discarded" ;;
        esac
    fi

    branch=$(git branch --show-current)
    target=$(_g_default_branch)

    if [ -z "$branch" ] || [ "$branch" = "$target" ]; then
        echo "gmr: you are on $target - make a feature branch first" >&2
        return 1
    fi

    # Nothing to merge is the commonest reason glab fails, and it fails only
    # after pushing. Check locally first, against the remote target if we have
    # it, so the answer matches what the server will see.
    local base ahead
    if git rev-parse --verify --quiet "origin/$target" >/dev/null; then
        base=origin/$target
    else
        base=$target
    fi
    ahead=$(git rev-list --count "$base..HEAD" 2>/dev/null || echo 0)
    if [ "$ahead" -eq 0 ]; then
        echo "gmr: $branch has no commits ahead of $base - nothing to merge" >&2
        return 1
    fi
    echo "$ahead commit(s) ahead of $base"

    # An existing MR is the other common failure, and it is one API call.
    if [ -n "$(_g_api merge_requests "?state=opened&source_branch=$branch" \
               | jq -r '.[0].iid // empty')" ]; then
        echo "gmr: an open MR already exists for $branch" >&2
        echo "     gmr list    to act on it" >&2
        return 1
    fi

    # -e -i puts the default on the line, already editable
    read -r -e -i "$(git log -1 --pretty=%s)" -p "title: " title </dev/tty
    [ -n "$title" ] || { echo "gmr: no title" >&2; return 1; }

    templates=$(_g_templates)
    if [ -n "$templates" ]; then
        tmpl=$(printf '%s\n(none)\n' "$templates" \
               | pick --prompt='template> ' --height=40%) || return 1
        [ "$tmpl" = "(none)" ] && tmpl=
    fi

    read -r -e -i "$target" -p "target branch: " target </dev/tty

    draft=$(menu_pick "draft merge request?" no yes) || return 1

    local assignee reviewer
    assignee=$(_g_pick_member assignee) || return 1
    reviewer=$(_g_pick_member reviewer) || return 1

    cmd=(glab mr create --title "$title" --target-branch "$target" --push)
    [ -n "$tmpl" ] && cmd+=(--template "$tmpl")
    [ "$draft" = yes ] && cmd+=(--draft)
    [ -n "$assignee" ] && cmd+=(--assignee "${assignee#* }")   # username half
    [ -n "$reviewer" ] && cmd+=(--reviewer "${reviewer#* }")

    # Readable on one line: quote only the arguments that contain spaces.
    printf '\n  '
    local a
    for a in "${cmd[@]}"; do
        case $a in
            *[[:space:]]*) printf '"%s" ' "$a" ;;
            *)             printf '%s ' "$a" ;;
        esac
    done
    printf '\n\n'

    read -r -p "run this? [y/N] " answer </dev/tty
    [ "$answer" = y ] || { echo "cancelled"; return 1; }

    if ! "${cmd[@]}"; then
        echo >&2
        echo "gmr: glab reported a failure. Common causes:" >&2
        echo "  - no commits between $target and $branch:" >&2
        echo "      git log $target..$branch --oneline" >&2
        echo "  - an MR already exists for this branch:" >&2
        echo "      glab mr list --source-branch $branch" >&2
        echo "  - your answers were saved; run gmr again to retry or discard" >&2
        return 1
    fi
}

# The merge-request LIST endpoint does not return head_pipeline - that field
# only appears when fetching a single MR. Rather than one call per row, fetch
# the project's pipelines once and join on the commit sha.
_g_mrs() {
    local mrs pipes query me
    query='?state=opened&per_page=30'

    if [ "${1:-}" = mine ]; then
        me=$(glab api user 2>/dev/null | jq -r '.username // empty')
        [ -n "$me" ] && query="$query&author_username=$me"
    fi

    mrs=$(_g_api merge_requests "$query") || return 1
    pipes=$(_g_api pipelines '?per_page=100') || pipes='[]'

    jq -r --argjson p "$pipes" '
        # sha -> status, newest first so the first entry per sha wins
        ($p | map({key: .sha, value: .status}) | from_entries) as $st
        | .[] | [.iid,
                 (.head_pipeline.status // $st[.sha] // "-"),
                 (.updated_at[5:16] | sub("T"; " ")),
                 .author.username, .source_branch, .title] | @tsv' <<< "$mrs" \
        | awk -F'\t' "$(_g_colour_awk)"'
             { printf "%-6s %s%-9s%s %-12s %-12s %-24s %s\n",
                      $1, col($2), $2, off(), $3, $4, $5, $6 }'
}

# Pipeline id of an MR's head commit, empty if it has none. The single-MR
# endpoint does carry head_pipeline, so one call is enough here.
_g_mr_pipeline() {
    _g_api "merge_requests/$1" \
        | jq -r '.head_pipeline.id // .pipeline.id // empty'
}

# Notes on an MR. system:true entries are GitLab's own event log ("changed
# title", "assigned to"), which drowns the actual discussion - hence the filter.
_g_notes() {
    _g_api "merge_requests/$1/notes" '?per_page=100&sort=asc' \
        | jq -r '.[] | select(.system | not)
                 | "── \(.author.username)  \(.created_at[0:16])\n\(.body)\n"'
}

_gmr_list() {
    local scope=${1:-} line iid action body pid

    while true; do
        line=$(_g_mrs "$scope" | pick --ansi --prompt='mr> ' --height=60% \
                  --header='enter: actions   esc: quit') || return 0
        [ -n "$line" ] || return 0
        iid=${line%% *}

        # The selected row already carries status, date, author, branch and
        # title, so reuse it as the menu header instead of refetching.
        action=$(menu_pick "MR !$iid
  $line
" pipeline view diff comments comment assign approve checkout browser merge back) \
            || continue

        case $action in
            pipeline)
                pid=$(_g_mr_pipeline "$iid")
                if [ -n "$pid" ]; then gjob "$pid"
                else echo "!$iid has no pipeline"; fi ;;
            view)     glab mr view "$iid" | ${PAGER:-less} -R ;;
            diff)     glab mr diff "$iid" | _g_colordiff | ${PAGER:-less} -R ;;
            comments)
                if [ -z "$(_g_notes "$iid")" ]; then
                    echo "no comments on !$iid"
                else
                    _g_notes "$iid" | ${PAGER:-less} -R
                fi ;;
            comment)
                read -r -e -p "comment: " body </dev/tty
                if [ -z "$body" ]; then
                    echo "cancelled"
                # `glab mr note -m` is deprecated in favour of the subcommand;
                # fall back to the old form on versions that lack it.
                elif glab mr note create --help >/dev/null 2>&1; then
                    glab mr note create "$iid" --message "$body"
                else
                    glab mr note "$iid" --message "$body"
                fi ;;
            assign)
                body=$(_g_pick_member assignee) || continue
                if [ -n "$body" ]; then
                    glab api -X PUT "projects/$(_g_project)/merge_requests/$iid" \
                        -f "assignee_id=${body%% *}" \
                        | jq -r '"assigned to \(.assignee.username // "nobody")"'
                else
                    echo "no user chosen"
                fi ;;
            approve)  glab mr approve "$iid" ;;
            checkout) glab mr checkout "$iid"; return 0 ;;   # you now want the shell
            browser)  glab mr view "$iid" --web ;;
            merge)
                read -r -p "merge !$iid? type yes: " action </dev/tty
                if [ "$action" = yes ]; then glab mr merge "$iid"
                else echo "cancelled"; fi ;;
            back)     continue ;;
        esac

        case $action in
            pipeline|view|diff|comments|back) ;;
            *) read -r -p "enter to return to the MR list... " _ </dev/tty ;;
        esac
    done
}
