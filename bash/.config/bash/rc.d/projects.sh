#@ 10 projects
# Project folders: numbered directories under $PROJECT_ROOT.

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/projects}"

# --- internal ---------------------------------------------------------------

# Next free 2-digit prefix: max+1, then walk forward past anything taken.
_proj_next_num() {
    local dir base num max=-1 next

    for dir in "$PROJECT_ROOT"/[0-9][0-9]-*/; do
        [ -d "$dir" ] || continue          # unmatched glob stays literal; skip it
        base=$(basename "$dir")
        num=$((10#${base:0:2}))            # 10# forces base 10 — 08/09 are not octal
        (( num > max )) && max=$num
    done

    next=$((max + 1))
    while compgen -G "$PROJECT_ROOT/$(printf '%02d' "$next")-*" >/dev/null; do
        next=$((next + 1))
    done

    if (( next > 99 )); then
        echo "projects: no free number below 100" >&2
        return 1
    fi

    printf '%02d' "$next"
}

# --- projects ---------------------------------------------------------------

#: pclone <url> [name]   clone a repo into ~/projects with the next free number
#>   pclone git@gitlab.com:dsoc/ecu-metrics.git
#>       -> ~/projects/03-ecu-metrics, and cds there
#>   pclone https://github.com/firecow/gitlab-ci-local.git ci-local
#>       -> ~/projects/04-ci-local  (second arg overrides the name)
pclone() {
    local url=$1 name=$2 num dest

    if [ -z "$url" ]; then
        echo "usage: pclone <url> [name]" >&2
        return 1
    fi

    mkdir -p "$PROJECT_ROOT" || return 1
    [ -n "$name" ] || name=$(basename "${url%/}" .git)   # works for https and ssh

    num=$(_proj_next_num) || return 1
    dest="$PROJECT_ROOT/$num-$name"

    git clone "$url" "$dest" || return 1
    cd "$dest" || return 1

    qgate . 2>/dev/null       # R1.2.3: install the quality gate on clone
}

#: p [n]                 cd to project n
#>   p          -> ~/projects
#>   p 3        -> ~/projects/03-ecu-metrics
#>   p 12       -> ~/projects/12-whatever  (no padding needed)
p() {
    local n=$1 pat matches

    if [ -z "$n" ]; then
        cd "$PROJECT_ROOT" || return 1
        return
    fi

    if ! [[ $n =~ ^[0-9]+$ ]]; then
        echo "p: '$n' is not a number" >&2
        return 1
    fi

    pat="$PROJECT_ROOT/$(printf '%02d' "$((10#$n))")-*"
    mapfile -t matches < <(compgen -G "$pat")

    case ${#matches[@]} in
        0)  echo "p: no project $n" >&2 ; return 1 ;;
        1)  cd "${matches[0]}" || return 1 ; pwd ;;
        *)  echo "p: $n is ambiguous:" >&2
            printf '  %s\n' "${matches[@]##*/}" >&2
            return 1 ;;
    esac
}

#: pl                    list projects
#>   pl
#>   pl | grep ecu         find one by name
#>   pl | wc -l            count them
pl() {
    local dir base found=0

    for dir in "$PROJECT_ROOT"/*/; do
        [ -d "$dir" ] || continue
        base=$(basename "$dir")
        found=1
        if [[ $base =~ ^[0-9][0-9]- ]]; then
            echo "$base"
        else
            echo "$base   (unnumbered)"
        fi
    done

    (( found )) || { echo "no projects in $PROJECT_ROOT" >&2; return 1; }
}

#: pp                    pick a project with fzf, cd there
#>   pp         then type part of a name and press enter
pp() {
    local choice
    choice=$(pl | fzf --prompt='project> ' --height=40%) || return 1
    choice=${choice%%   (unnumbered)}                    # strip the marker
    [ -n "$choice" ] || return 1
    cd "$PROJECT_ROOT/$choice" || return 1
}
