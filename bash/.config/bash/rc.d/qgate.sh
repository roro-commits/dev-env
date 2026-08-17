#@ 30 quality gate
# Personal quality gate: pre-commit driven by one config, everywhere.

# --- quality gate -----------------------------------------------------------

PC_CONFIG="${PC_CONFIG:-$HOME/.config/pre-commit/global.yaml}"

#: qgate [dir]           install the personal quality gate in a repo
#>   qgate                 current repo
#>   qgate ~/projects/03-ecu-metrics
#>       installs two git hooks pointing at ~/.config/pre-commit/global.yaml:
#>         .git/hooks/pre-commit   the 12 local hooks, run on git commit
#>         .git/hooks/pre-push     glab ci lint, run on git push
#>       the project's own .pre-commit-config.yaml is then never read here
#>       nothing is checked at install time - run qrun to check
qgate() {
    local dir=${1:-.}

    if [ ! -f "$PC_CONFIG" ]; then
        echo "qgate: no config at $PC_CONFIG (stow the pre-commit package)" >&2
        return 1
    fi
    if ! command -v pre-commit >/dev/null; then
        echo "qgate: pre-commit not installed" >&2
        return 1
    fi

    (
        cd "$dir" || exit 1
        git rev-parse --git-dir >/dev/null 2>&1 || { echo "qgate: not a git repo" >&2; exit 1; }

        # pre-commit for the fast local hooks, pre-push for glab ci lint
        pre-commit install            -c "$PC_CONFIG" || exit 1
        pre-commit install --hook-type pre-push -c "$PC_CONFIG" || exit 1

        echo "qgate: installed in $(pwd)"
    )
}

#: qrun [scope]          run the gate now, on a chosen scope
#>   qrun                  staged files only (what a commit would check)
#>   qrun -b               everything your branch changed vs its base
#>   qrun -a               the whole repo (expect other people's debt)
#>   qrun -f a.py b.sh     named files
#>   qrun -p               the project's own .pre-commit-config.yaml, not yours
#>                         (needs network the first time: it clones the hook
#>                          repos into ~/.cache/pre-commit. use it to check
#>                          your local gate still agrees with what CI runs)
#>
#>   skipping hooks (SKIP is pre-commit's own, inherited by any command):
#>     SKIP=mypy qrun -a             skip one hook
#>     SKIP=mypy,ruff-check qrun -a  skip several
#>     SKIP=mypy git commit          works on real commits too
#>
#>   bypassing git hooks entirely (avoid: this skips gitleaks as well):
#>     git commit --no-verify
#>     git push   --no-verify
#>
#>   other pre-commit env vars:
#>     PRE_COMMIT_COLOR=never        plain output, good for piping to a file
#>     PRE_COMMIT_ALLOW_NO_CONFIG=1  do not fail in a repo with no config
#>
#>   hook ids you can name in SKIP:
#>     hygiene merge-conflict case-conflict large-files gitleaks yamllint
#>     shellcheck ruff-check ruff-format mypy gofmt rumdl glab-ci-lint
# Commit that HEAD and the base branch diverged from, so a branch-scoped run
# covers your commits and nobody else's.
_q_base() {
    local ref
    for ref in \
        "$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" \
        origin/main origin/master main master
    do
        [ -n "$ref" ] || continue
        git rev-parse --verify --quiet "$ref" >/dev/null || continue
        git merge-base HEAD "$ref" && return 0
    done
    echo "qrun: no base branch found (tried origin/HEAD, main, master)" >&2
    return 1
}

qrun() {
    command -v pre-commit >/dev/null || { echo "qrun: pre-commit not installed" >&2; return 1; }

    local base
    case "${1:-}" in
        -a|--all)
            pre-commit run --all-files --show-diff-on-failure -c "$PC_CONFIG" ;;
        -b|--branch)
            base=$(_q_base) || return 1
            pre-commit run --from-ref "$base" --to-ref HEAD \
                           --show-diff-on-failure -c "$PC_CONFIG" ;;
        -f|--files)
            shift
            [ $# -gt 0 ] || { echo "qrun -f needs file names" >&2; return 1; }
            pre-commit run --files "$@" --show-diff-on-failure -c "$PC_CONFIG" ;;
        -p|--project)
            # No -c: pre-commit falls back to ./.pre-commit-config.yaml, which
            # is what CI runs. Divergence between this and your gate is the
            # thing that makes a commit pass locally and fail in the pipeline.
            [ -f .pre-commit-config.yaml ] || {
                echo "qrun: this repo has no .pre-commit-config.yaml" >&2; return 1; }
            pre-commit run --all-files --show-diff-on-failure ;;
        "")
            pre-commit run --show-diff-on-failure -c "$PC_CONFIG" ;;
        *)
            pre-commit run --show-diff-on-failure -c "$PC_CONFIG" "$@" ;;
    esac
}

#: qdoctor               check the gate's tools are present and on PATH
#>   qdoctor
qdoctor() {
    local t missing=0
    echo "config: $PC_CONFIG"
    [ -f "$PC_CONFIG" ] || { echo "  MISSING"; missing=1; }

    for t in pre-commit yamllint shellcheck ruff mypy gofmt rumdl gitleaks \
             glab gitlab-ci-local docker jq \
             pc-hygiene pc-case-conflict pc-large-files pc-syntax pc-glab-lint \
             g-trace g-ptrace g-clean cil-vars g-oidc; do
        if command -v "$t" >/dev/null; then
            printf '  ok      %s\n' "$t"
        else
            printf '  MISSING %s\n' "$t"
            missing=1
        fi
    done

    if (( missing )); then
        case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *) echo
               echo "  \$HOME/.local/bin is not on PATH - the pc-* and g-*"
               echo "  scripts are linked but nothing can find them:"
               echo "    home.sessionPath = [ \"\$HOME/.local/bin\" ];  in home.nix" ;;
        esac
        echo "fix the above, or comment out the matching hook"
    fi
    return $missing
}
