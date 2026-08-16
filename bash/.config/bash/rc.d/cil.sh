#@ 35 local pipeline runs
# --- run pipelines locally --------------------------------------------------

#: cil [scope]           run .gitlab-ci.yml locally in docker, before pushing
#>   cil                   the whole pipeline
#>   cil -l                list jobs without running anything
#>   cil -j                pick one job with fzf and run it
#>   cil build             run the job named build
#>   cil -n build          run build plus the jobs it needs
#>
#>   variables the real pipeline gets from GitLab must be supplied locally:
#>     ./.gitlab-ci-local-variables.yml   per repo   (never commit this)
#>     ~/.gitlab-ci-local/variables.yml   shared across repos
#>
#>   keep both out of git for good:
#>     git config --global core.excludesFile ~/.config/git/ignore
#>     printf '%s\n' .gitlab-ci-local/ .gitlab-ci-local-variables.yml \
#>       >> ~/.config/git/ignore
cil() {
    command -v gitlab-ci-local >/dev/null || {
        echo "cil: gitlab-ci-local not installed (add pkgs.gitlab-ci-local)" >&2; return 1; }
    [ -f .gitlab-ci.yml ] || { echo "cil: no .gitlab-ci.yml here" >&2; return 1; }
    docker info >/dev/null 2>&1 || { echo "cil: docker daemon not reachable" >&2; return 1; }

    local job
    case "${1:-}" in
        -l|--list)
            gitlab-ci-local --list ;;
        -j|--job)
            # column 1 of --list is the job name; drop the header row
            job=$(gitlab-ci-local --list 2>/dev/null \
                  | awk 'NR > 1 && NF { print $1 }' \
                  | fzf --prompt='job> ' --height=40%) || return 1
            [ -n "$job" ] || return 1
            gitlab-ci-local "$job" ;;
        -n|--needs)
            shift
            [ $# -gt 0 ] || { echo "cil -n needs a job name" >&2; return 1; }
            gitlab-ci-local --needs "$@" ;;
        *)
            gitlab-ci-local "$@" ;;
    esac
}
