# ~/.config/bash/projects.sh
# R1 — project navigation.
# Sourced from ~/.bashrc, NOT executed. A script runs in a child shell and a
# child shell cannot change the parent's directory, so anything that cds you
# must be a function living in your own shell.
#
#   dev-env/bash/.config/bash/projects.sh   (stow package)
#   ~/.bashrc:  [ -f ~/.config/bash/projects.sh ] && . ~/.config/bash/projects.sh

PROJECT_ROOT="${PROJECT_ROOT:-$HOME/projects}"

# --- internal ---------------------------------------------------------------

# Print the next free 2-digit prefix. Starts at max+1, then walks forward
# until it finds a number no directory is using.
_proj_next_num() {
    local dir base num max=-1 next

    for dir in "$PROJECT_ROOT"/[0-9][0-9]-*/; do
        [ -d "$dir" ] || continue          # no match: glob stays literal, skip
        base=$(basename "$dir")
        num=$((10#${base:0:2}))            # 10# forces base 10 — see note below
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

# --- public -----------------------------------------------------------------

# pclone <url> [name]   clone into $PROJECT_ROOT as NN-name, then cd there
pclone() {
    local url=$1 name=$2 num dest

    if [ -z "$url" ]; then
        echo "usage: pclone <url> [name]" >&2
        return 1
    fi

    mkdir -p "$PROJECT_ROOT" || return 1
    [ -n "$name" ] || name=$(basename "$url" .git)

    num=$(_proj_next_num) || return 1
    dest="$PROJECT_ROOT/$num-$name"

    git clone "$url" "$dest" || return 1
    cd "$dest" || return 1

    # R1.2.3 hook point — pre-commit install goes here once R2 exists.
}

# p [n]   cd to project n, or to $PROJECT_ROOT with no argument
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
        1)  cd "${matches[0]}" || return 1 ;;
        *)  echo "p: $n is ambiguous:" >&2
            printf '  %s\n' "${matches[@]##*/}" >&2
            return 1 ;;
    esac
}

# pl   list projects
pl() {
    local dir
    for dir in "$PROJECT_ROOT"/[0-9][0-9]-*/; do
        [ -d "$dir" ] || { echo "no projects in $PROJECT_ROOT" >&2; return 1; }
        basename "$dir"
    done
}
