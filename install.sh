#!/usr/bin/env bash
# install.sh - first-run bootstrap for this dev-env tree.
#
# dstow, reload and the rest are functions defined in the files this installs,
# so none of them exist yet the first time. This script uses plain stow and
# nothing else. After it runs once, use dstow.
#
#   cd ~/.dev-env/dev-env
#   unzip -o ~/Downloads/dev-env-packages.zip
#   bash install.sh

set -uo pipefail

DEV_ENV=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$DEV_ENV" || exit 1

command -v stow >/dev/null || {
    echo "install: stow not found. Add pkgs.stow to home.nix first." >&2
    exit 1
}

# Every top-level directory that looks like a stow package.
packages=()
for d in */; do
    d=${d%/}
    case $d in
        .git|result|*.md) continue ;;
    esac
    [ -d "$d" ] || continue
    # A package contains a dotdir or .local, not loose files.
    if [ -d "$d/.config" ] || [ -d "$d/.local" ]; then
        packages+=("$d")
    fi
done

if [ ${#packages[@]} -eq 0 ]; then
    echo "install: no stow packages found in $DEV_ENV" >&2
    exit 1
fi

echo "packages: ${packages[*]}"

# Scripts lose their execute bit through zip on some platforms.
if [ -d bin/.local/bin ]; then
    chmod +x bin/.local/bin/* 2>/dev/null
fi

# Remove symlinks that point outside this tree. They are leftovers from an
# older location and are exactly what makes stow abort "not owned by stow".
for pkg in "${packages[@]}"; do
    while IFS= read -r target; do
        link="$HOME/$target"
        [ -L "$link" ] || continue
        case "$(readlink -f "$link")" in
            "$DEV_ENV"/*) ;;
            *) echo "  removing stale link $link"; rm -f "$link" ;;
        esac
    done < <(cd "$pkg" && find . -mindepth 1 -printf '%P\n')
done

# --no-folding so stow links individual files rather than whole directories,
# which lets it coexist with home-manager in ~/.config.
stow --no-folding -R -v -t "$HOME" "${packages[@]}" || exit 1

# The scripts are useless if nothing searches for them, and this is the
# failure that looks like "missing" when the symlinks are plainly there.
path_ok=0
case ":$PATH:" in
    *":$HOME/.local/bin:"*) path_ok=1 ;;
esac

echo
if [ "$path_ok" -eq 0 ]; then
    echo "WARNING: \$HOME/.local/bin is not on PATH, so the pc-* and g-*"
    echo "         scripts will report as missing even though they linked."
    echo
    echo "  now:       export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo "  for good:  home.sessionPath = [ \"\$HOME/.local/bin\" ];  in home.nix"
    echo
fi

echo "linked. Two things left:"
echo
echo "  1. home.nix, inside programs.bash:"
echo "       initExtra = ''"
echo "         [ -f ~/.config/bash/init.sh ] && . ~/.config/bash/init.sh"
echo "         board"
echo "       '';"
echo "     then: home-manager switch"
echo
echo "  2. in this shell:"
echo "       . ~/.config/bash/init.sh"
echo "       qdoctor"
