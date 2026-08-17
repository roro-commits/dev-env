# dev-env shell layer

Thirty commands. Three jobs: move between projects, stop broken code reaching
the pipeline, drive GitLab without a browser.

## Start here

Three commands do most of the work. Everything else can wait until you need it.

```bash
gstats 200      # once, before the gate changes anything - the baseline
qgate           # per repo, installs the hooks
qrun -b         # before every push
```

`gnow` replaces opening a browser tab; `gmr` is the hub view. `gfail` when
something breaks, if you will write the root cause properly.

**Start with `dev-help`.** It lists everything; `dev-help gpipe` shows examples
for one. The help is read out of the source at runtime, so it cannot go stale.

## Layout

```
bash/.config/bash/
├── init.sh          sourced by home.nix; sources rc.d/*.sh
└── rc.d/
    ├── projects.sh  p pl pp pclone
    ├── devenv.sh    de dstow dtake
    ├── aliases.sh   git and nix shorthands
    ├── qgate.sh     qgate qrun qdoctor
    ├── cil.sh       cil
    ├── glab.sh      gauth grepo gpipe gjob gart gview gwatch gnow
    ├── glab-mr.sh   gmr
    ├── gvar.sh      gvar
    ├── gfail.sh     gfail gmine gstats gcode
    ├── focus.sh     focus board
    └── help.sh      dev-help m

bin/.local/bin/      pc-* (pre-commit hooks), g-trace, g-ptrace, g-clean,
                     cil-vars, g-oidc
pre-commit/.config/pre-commit/global.yaml
zellij/.config/zellij/  layouts/, keybinds-snippet.kdl
```

Load order does not matter — no file depends on another at source time.

## Install

First time, or on a new machine - `dstow` is one of the functions being
installed, so it does not exist yet:

```bash
cd ~/.dev-env/dev-env
unzip -o ~/Downloads/dev-env-packages.zip
bash install.sh
. ~/.config/bash/init.sh
qdoctor
```

`install.sh` needs only stow. It finds the packages itself, restores execute
bits that zip drops, clears symlinks pointing at an older tree, and stows with
`--no-folding` so it coexists with home-manager in `~/.config`.

After that, `dstow` handles new files and `reload` picks up edits.

`home.nix`, inside `programs.bash`:

```nix
  initExtra = ''
    [ -f ~/.config/bash/init.sh ] && . ~/.config/bash/init.sh
    board
  '';
```

## Adding a command

Write a function in an `rc.d/*.sh` file with a `#:` line and `#>` examples.
A `#@ <sort> <title>` line at the top of the file gives it a heading in
`dev-help`; a new file joins the grouped list by existing, not by being
registered.

```bash
#: mycmd [arg]           one line, shown in dev-help
#>   mycmd thing           an example
mycmd() { ... }
```

`dstow bash` if the file is new. Nothing to register.

## The quality gate

`global.yaml` reimplements the JLR gate with `repo: local` hooks only, so it
needs no network and behaves the same everywhere. Cost: it can drift from what
CI runs — `qrun -p` runs the project's own config when that matters.

```
qgate      install the hooks in a repo (once)
qrun       staged      qrun -b  branch      qrun -a  whole repo
qrun -f    named files qrun -p  the project's config, i.e. what CI does
```

`SKIP=mypy qrun -a` skips a hook — pre-commit's own variable, inherited.

## Running pipelines locally

`cil` wraps gitlab-ci-local: it parses your `.gitlab-ci.yml`, resolves includes
and `extends`, and runs the jobs in Docker. It catches the class of failure
that has nothing to do with the runner - a typo, a wrong path, a missing tool,
a `needs` pointing at the wrong stage.

```
cil -l          list jobs        cil build      run one
cil -j          pick one         cil -n build   plus what it needs
cil -s build    forward the ssh agent, for this run only
cil -v          variables template for this repo, grouped by job
cil -v --home   the shared ones, once, for every project
cil -t NAME     a fake id_token, so a job that reads one can run
```

`cil -v` reads the *merged* pipeline, so it sees what the included templates
reference too. Each variable is annotated with the jobs that use it, values you
already have are carried over, and credential-looking names become `$NAME`
references with a matching `.env` stub to fill in and source. Both generated
files are gitignored automatically through `core.excludesFile`, never
`.gitignore`, which would be committed.

Variables that are identical everywhere belong in `~/.gitlab-ci-local/
variables.yml` via `cil -v --home`; anything project-shaped stays in the repo
file. Putting `CI_REGISTRY_IMAGE` in the home file is the mistake that fails
silently.

Three things it cannot reproduce, and no local tool can: `CI_JOB_TOKEN`,
real OIDC `id_tokens`, and the runner's network position. `cil -t` mints a
token with GitLab's claim shape so a script can be exercised, but nothing will
verify it - that is the design working, not a gap.

`-s` is opt-in per run for a reason: the agent socket lets every script in the
pipeline, including included templates you did not write, sign as you.

### What the gate checks first

`pc-syntax` runs before every linter and asks only: does this file parse? It
uses a real parser per language - `bash -n`, `ast.parse`, `jq`, `node --check`,
`gofmt -e`, `tomllib`, PyYAML, `nix-instantiate --parse` - so a brace inside a
string never trips it. An unclosed bracket fails in a second instead of six
minutes.

YAML gets one extra check: duplicate keys. They are legal YAML and silently
keep the last value, which in a `.gitlab-ci.yml` means one job quietly
replacing another.

## The hub

`gmr` is the view worth defaulting to. Each row carries the MR's pipeline
status, and from a row you reach the jobs, the trace, the artifacts, the diff,
the comments, approve and merge. `gnow` answers the same question in one line
when you do not need to act.

## The failure record

`gfail` writes one markdown file per failure to `~/Documents/pipeline-failures`
plus a TSV index. `gfail fix` finds the first pipeline that passed afterwards
and attaches the commits and diff between them.

Three sections, and the middle one is why this exists:

- **Cause** — what the tool objected to. Already in the trace; one line.
- **Root cause** — why the mistake was possible at all. Not the error: the gap
  that let it through. Keep asking why until the answer is about a process
  rather than a keystroke.
- **Fix** — what changed, *and* what stops the class of failure recurring. If
  that second part is empty, the root cause is still a symptom.

`gmine` pairs failures with fixes across the whole project, not just yours —
how other people's pipelines break and what fixed them. Saved as `noted`, so it
never counts as work you owe. `gstats` needs no logging at all; it computes
from the API. `gcode` explains an exit code and counts how often you have hit
it.

The diff attached to a record is a **candidate** set, not a cause. Unrelated
commits land in it. Narrowing it is the part only you can do.

## Navigation

Every command that browses a list loops: doing something returns you to the
list, **esc goes up one level**, and at the top level esc quits. The header
line always states the keys.

Looping: `gpipe` `gjob` `gmr list` `gfail pick` `gfail find` `gmine`
`gvar browse` `zjk` `m`

Single-shot on purpose: forms (`gmr` create, `gvar set`, `gfail` capture) and
anything that changes state and hands you back to the shell (`pp`, `zj`,
`grepo`, `cil`).

To check the invariant after adding a command:

```bash
awk '
  /^[a-z_][a-zA-Z0-9_-]*\(\) \{/ { fn=$1; sub(/\(\).*/,"",fn); body=""; inf=1 }
  inf { body = body "\n" $0 }
  inf && /^\}/ {
      if (body ~ /pick |menu_pick |fzf /)
          printf "  %-18s %s\n", fn, (body ~ /while true/) ? "loops" : "single-shot"
      inf=0
  }' ~/.config/bash/rc.d/*.sh | sort -k2
```

## After changing anything

A shell reads `init.sh` once, at startup. Editing a file does not reach shells
that are already running — and a zellij session left open for days keeps
whatever was current when its panes started. That is the usual reason a command
seems missing right after installing it.

```bash
reload        # re-source in this shell
```

`reload` redefines functions but cannot un-define ones you deleted from the
files. For that, open a new shell.

## Zellij

`zj 5` attaches to a session named after project 05, creating it if absent. A
session outlives the terminal window, so tomorrow's `zj 5` returns the panes,
directories and scrollback you left.

Three ways to make a layout permanent, weakest to strongest:

- **Per project** — arrange panes by hand, `zjsave`. It writes
  `zellij/.config/zellij/layouts/<session>.kdl` into this repo and stows it;
  `zj` picks up a layout matching the project name automatically.
- **Every new session** — `default_layout "dev"` in `config.kdl`.
- **Exactly as you left it** — `session_serialization true` in `config.kdl`
  makes zellij restore exited sessions pane for pane, no layout file involved.

`zf <command>` throws anything into a floating pane; the keybind snippet in
`layouts/keybinds-snippet.kdl` binds the useful ones to Alt keys.

## Command index

```
projects     p  pl  pp  pclone
dev-env      de  dstow  dtake  reload
gate         qgate  qrun  qdoctor
local runs   cil
gitlab       gauth  grepo  gpipe  gjob  gart  gview  gwatch  gnow  gmr  gvar
records      gfail  gmine  gstats  gcode
zellij       zj  zjl  zjk  zf  zjwhere  zjsave  zjlayouts
focus        focus  board
help         dev-help  m  aliases
```

## Rough edges

- `glab` mostly *adds* flags. Actual removals are rare and reach you as a
  deprecation warning long before they break — `--message` and the `GLAB_`
  env prefix both still work. Nix pins the version anyway, so a bump is a
  thing you choose. The real protection is that lists go through `glab api`
  (versioned JSON) and only actions use subcommands.
- `rumdl`, `gitleaks` and `gvar` flag spellings were verified once. Re-check
  after a nixpkgs bump.
- `cil -t` needs `pyjwt`: `pip install --break-system-packages pyjwt
  cryptography`. Whether gitlab-ci-local expands a `$NAME` reference from the
  environment is version-dependent - check with `cil -l` before trusting it.
- Zellij differs between machines if your package sources differ. `zj` from
  inside a session switches on new versions, opens the session manager on
  middling ones, and asks you to detach on old ones. `zjwhere` says which.
- Write paths, all confirmed: `gmr new`, `gvar set`, `gvar rm` (type the key
  back), `zjk` (type `kill` for a running session), `gauth rotate`.
- Porting to Woodpecker or GitHub Actions means putting `_ci_*` verbs in front
  of the ~20 direct `glab api` calls. Worth doing with a second provider in
  hand, not before.
