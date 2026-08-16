#@ 35 local pipeline runs
# --- run pipelines locally --------------------------------------------------

#: cil [scope]           run .gitlab-ci.yml locally in docker, before pushing
#>   cil                   the whole pipeline
#>   cil -l                list jobs without running anything
#>   cil -j                pick one job with fzf and run it
#>   cil build             run the job named build
#>   cil -n build          run build plus the jobs it needs
#>   cil -s build          same, with your ssh agent forwarded
#>   cil -v                variables template for this repo, grouped by job
#>   cil -v --home         the shared ones, in ~/.gitlab-ci-local/variables.yml
#>
#>   -v reads the merged pipeline, so it sees what the included templates
#>   reference too. each line is annotated with the jobs that use it, and
#>   any value you already have - repo file, home file, environment - is
#>   carried over rather than blanked.
#>
#>   credential-looking names (KEY, TOKEN, PASSWORD, SECRET) are written as
#>   $NAME rather than a blank, and a matching .env stub is generated:
#>     . .gitlab-ci-local-variables.env    after you fill it in
#>   so secrets live in your environment, not in a file that could be
#>   committed. verify your gitlab-ci-local expands them - `cil -l` first.
#>
#>   both files are gitignored automatically via core.excludesFile, which
#>   lives in your home directory - never .gitignore, which is tracked and
#>   would reach the remote.
#>
#>   put what is the same everywhere in the home file once; the repo file
#>   is for the odds and ends. neither belongs in git.
#>
#>   -s is per run, never default. it mounts $SSH_AUTH_SOCK into the job so
#>   a script can git clone or ssh as you. the container gets the socket,
#>   not the key - but the agent still signs whatever it is asked to, and
#>   the scripts include templates you did not write. use it for the one
#>   job that needs it, not for the whole pipeline.
#>
#>   with -s, also set in ~/.gitlab-ci-local/variables.yml:
#>     SSH_AUTH_SOCK: /ssh-agent
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

    # SSH is opt-in per run, never default: mounting the agent socket lets
    # every script in the pipeline - including included templates you did not
    # write - sign with your key. The container gets the socket, not the key,
    # but the agent will still sign whatever it is asked to.
    local ssh_opt=()
    if [ "${1:-}" = "-s" ] || [ "${1:-}" = "--ssh" ]; then
        shift
        if [ -z "${SSH_AUTH_SOCK:-}" ]; then
            echo "cil: no ssh-agent running (SSH_AUTH_SOCK unset)" >&2
            return 1
        fi
        ssh_opt=(--volume "$SSH_AUTH_SOCK:/ssh-agent")
        echo "cil: forwarding the ssh agent - jobs can sign as you"
    fi

    local job
    case "${1:-}" in
        -v|--vars)
            shift
            cil-vars "$@" ;;
        -l|--list)
            gitlab-ci-local "${ssh_opt[@]}" --list ;;
        -j|--job)
            # column 1 of --list is the job name; drop the header row
            job=$(gitlab-ci-local --list 2>/dev/null \
                  | awk 'NR > 1 && NF { print $1 }' \
                  | fzf --prompt='job> ' --height=40%) || return 1
            [ -n "$job" ] || return 1
            gitlab-ci-local "${ssh_opt[@]}" "$job" ;;
        -n|--needs)
            shift
            [ $# -gt 0 ] || { echo "cil -n needs a job name" >&2; return 1; }
            gitlab-ci-local "${ssh_opt[@]}" --needs "$@" ;;
        *)
            gitlab-ci-local "${ssh_opt[@]}" "$@" ;;
    esac
}
