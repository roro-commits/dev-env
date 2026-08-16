# ~/.config/bash/init.sh
# Loader. home.nix sources only this file; it sources everything in rc.d/.
#
#   programs.bash.initExtra:
#     [ -f ~/.config/bash/init.sh ] && . ~/.config/bash/init.sh
#
# Load order is deliberately not significant: no file depends on another at
# source time, and dev-help reads rc.d/ when it runs, not when it loads.
# Adding a command means dropping a file in rc.d/ and opening a new shell.

DEV_BASH_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEV_RC_DIR="$DEV_BASH_DIR/rc.d"

for _f in "$DEV_RC_DIR"/*.sh; do
    [ -r "$_f" ] || continue

    # A syntax error aborts sourcing at that line, so every function below it
    # goes missing while its #: help comment still shows up in dev-help. Check
    # first and say so, rather than failing silently at shell start.
    if ! bash -n "$_f" 2>/dev/null; then
        printf 'dev-env: %s has a syntax error, skipped:\n' "${_f##*/}" >&2
        bash -n "$_f" 2>&1 | sed 's/^/  /' >&2
        continue
    fi

    # shellcheck source=/dev/null
    . "$_f"
done
unset _f
