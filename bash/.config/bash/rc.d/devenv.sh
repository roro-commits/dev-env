#@ 20 dev-env
# The dev-env repo itself: navigating it and keeping ~ linked to it.

DEV_ENV="${DEV_ENV:-$HOME/.dev-env/dev-env}"

# --- dev-env ----------------------------------------------------------------

#: de [pkg]              cd to where a package's files actually live
#>   de                    -> ~/.dev-env/dev-env
#>   de helix              -> ~/.dev-env/dev-env/helix/.config/helix
#>   de bin                -> ~/.dev-env/dev-env/bin/.local/bin
#>   de <TAB>              completes package names
de() {
    local dir="$DEV_ENV" only

    if [ -n "${1:-}" ]; then
        dir="$DEV_ENV/$1"
        [ -d "$dir" ] || { echo "de: no package '$1'" >&2; return 1; }

        # Walk down through single-child directories, so helix/.config/helix
        # lands you on the toml files instead of an empty .config.
        while [ "$(find "$dir" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]; do
            only=$(find "$dir" -mindepth 1 -maxdepth 1)
            [ -d "$only" ] || break        # a lone file means we have arrived
            dir=$only
        done
    fi

    cd "$dir" || return 1
}

complete -W "bash helix zellij home-manager pre-commit bin" de

# --- stow -------------------------------------------------------------------

#: dstow [pkg...]        relink packages into ~ (clears stale links first)
#>   dstow                 all packages
#>   dstow bash            just one
#>   run after adding or renaming a file; editing needs no restow
dstow() {
    local pkgs=("$@") pkg target link
    [ ${#pkgs[@]} -gt 0 ] || pkgs=(bash helix zellij home-manager pre-commit bin)

    # Remove symlinks pointing outside $DEV_ENV. These are leftovers from an
    # old tree and are exactly what makes stow abort "not owned by stow".
    for pkg in "${pkgs[@]}"; do
        while IFS= read -r target; do
            link="$HOME/$target"
            [ -L "$link" ] || continue
            case "$(readlink -f "$link")" in
                "$DEV_ENV"/*) ;;
                *) echo "dstow: removing stale link $link" ; rm "$link" ;;
            esac
        done < <(cd "$DEV_ENV/$pkg" 2>/dev/null && find . -mindepth 1 -printf '%P\n')
    done

    ( cd "$DEV_ENV" && stow --no-folding -R -v -t "$HOME" "${pkgs[@]}" )
}

#: dtake <pkg> <file>    adopt an existing config file into dev-env
#>   dtake bash ~/.config/bash/aliases.sh
#>       moves it into the bash package and links it back
#>   dtake helix ~/.config/helix/config.toml
dtake() {
    local pkg=$1 src=$2 abs rel dest

    if [ -z "$pkg" ] || [ -z "$src" ]; then
        echo "usage: dtake <pkg> <file>" >&2
        return 1
    fi

    abs="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
    rel=${abs#"$HOME"/}
    if [ "$rel" = "$abs" ]; then
        echo "dtake: $abs is not under $HOME" >&2
        return 1
    fi

    dest="$DEV_ENV/$pkg/$rel"
    mkdir -p "$(dirname "$dest")" || return 1
    mv -n "$abs" "$dest" || return 1
    echo "dtake: $rel -> $pkg"

    dstow "$pkg"
}

#: reload                re-source the dev-env shell files in this shell
#>   reload                after editing or unzipping a new version
#>
#>   a shell reads init.sh once, at startup. long-lived panes - a zellij
#>   session left open for days - keep running whatever was current when
#>   they started. this is why a command can be "missing" right after you
#>   install it.
#>
#>   redefines functions, but does not remove ones deleted from the files:
#>   for that, open a new shell.
reload() {
    local init="${DEV_BASH_DIR:-$HOME/.config/bash}/init.sh"
    if [ ! -r "$init" ]; then
        echo "reload: no $init" >&2
        return 1
    fi
    # shellcheck source=/dev/null
    . "$init" && echo "reloaded from $init"
}
