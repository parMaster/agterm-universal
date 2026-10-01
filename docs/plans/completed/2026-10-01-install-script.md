# One-command install script

**Goal:** Replace the six copy-paste steps in README's "Installing (or updating) a build" with one
`install.sh` that does all of them.

**Kind of change:** feature

## Intent

Installing or updating today means copying and running six separate command blocks from the README.
None of them needs a human decision in between, so they should be one script. A fresh Mac should be
able to install without cloning this repo and without the `gh` CLI. README keeps a short section:
the one-liner, what the script does, and the manual "quit and reopen" note.

```
before:  brew uninstall → download → unzip+move → xattr → symlink → verify   (6 pastes)

after:   ./install.sh [tag]
           download → check archs → brew uninstall cask → swap app → xattr → symlink → verify
           └── nothing on disk changes until here ──┘
```

## Decisions

- **One script at the repo root, `install.sh`, bash** — runs both from a clone (`./install.sh`) and
  piped (`curl -fsSL https://raw.githubusercontent.com/parMaster/agterm-universal/main/install.sh | bash`,
  with a tag: `… | bash -s -- v0.33.1`). Dropped: a Makefile target (needs a clone) and a Homebrew
  tap/cask (a second repo to maintain for one app).
- **Download with `curl` only, no `gh`** — the repo is public, so release assets download without a
  login. This drops the "no `gh`? download by hand" branch from the README. Dropped: `gh` first with
  a `curl` fallback — two code paths for the same result.
- **Latest tag comes from the `/releases/latest` redirect, not the REST API** — the API has a
  60-requests/hour limit for anonymous callers; the redirect doesn't.
- **Optional tag argument, with or without the `-universal` suffix** — `v0.33.1` and
  `v0.33.1-universal` both install the same release. No argument = latest.
- **Download and check before touching anything installed** — the unzipped app's `agterm` binary
  must report both `arm64` and `x86_64` before the Homebrew cask is removed or
  `/Applications/agterm.app` is replaced. A failed or wrong download leaves the working install as
  it was. This reorders the README's steps (cask removal moves after the download).
- **Work in a `mktemp -d` directory removed on exit** — instead of the fixed `/tmp/agterm-install`.
- **Homebrew is optional** — if `brew` isn't on `PATH`, skip the cask removal and the `agtermctl`
  symlink, and print the `ln -sf` line for the person to run with a directory of their choice.
  Dropped: guessing `/usr/local/bin`, which may not exist or be writable.
- **Never quits or relaunches agterm** — unchanged from README step 7. The script ends by saying
  that a running agterm keeps the old version until it's reopened.

## Constraints / out of scope

- Never `brew uninstall --zap` — it deletes `~/Library/Application Support/agterm`, which breaks a
  running instance's control socket.
- No prompts: under `curl | bash` stdin is the script itself, so nothing can read from it.
- No changes to the workflows or the release asset name.
- No uninstall command, no auto-update, no version check to skip an already-current install.

## Traps

- The asset name contains the upstream tag: `agterm-<upstream-tag>-universal.zip`, released under
  tag `<upstream-tag>-universal` (`.github/workflows/build-universal.yml`, "Package app" and
  "Publish release"). The download URL can't be built without first knowing the tag.
- The zip is made with `ditto -c -k --keepParent`, so it unpacks to a single top-level `agterm.app`
  (same workflow, "Package app").
- `brew uninstall --cask agterm` removes `/Applications/agterm.app` and the `agtermctl` symlink
  itself, so it must run before the new app is moved in, not after.
- `codesign -dv` writes its output to stderr.
- `shellcheck` is not installed on this Mac; `bash -n` is the only local syntax check unless it gets
  installed.

## Definition of Done

- [x] `./install.sh` with no argument installs the latest release — proof: run it on this Mac (it
      replaces the installed app, so get the user's go-ahead first); it exits 0 and prints
      `x86_64 arm64`, the ad-hoc signature line, and the installed tag (`v0.34.0-universal` today).
- [x] A tag argument works in both forms — proof: the resolved download URL is the same for
      `v0.33.1` and `v0.33.1-universal` and returns HTTP 200 (`curl -fsIL`), without doing a second
      full install.
- [x] A bad tag changes nothing — proof: `./install.sh v0.0.0` exits non-zero with a clear message,
      and `/Applications/agterm.app` has the same modification time as before.
- [x] `agtermctl` is on `PATH` after the run — proof: `agtermctl --help` exits 0 and
      `readlink "$(brew --prefix)/bin/agtermctl"` points into `/Applications/agterm.app`.
- [x] The piped form works — proof: `curl -fsSL <raw url> | bash -s -- <tag>` after the push, or
      `bash -s -- <tag> < install.sh` before it, ends the same way as the first item.
- [x] No temp files are left behind — proof: the work directory printed by the script no longer
      exists after it exits, on both success and the bad-tag failure.
- [x] README's install section is the one-liner, a short list of what the script does, the
      "never `--zap`" warning, the quit-and-reopen note, and the Gatekeeper right-click fallback —
      proof: `grep -n "gh release download\|/tmp/agterm-install" README.md` prints nothing.

## Wrap-up

- [x] syntax check passes: `bash -n install.sh` (no test suite in this repo)
- [x] linter: skipped, `shellcheck` is not installed on this Mac
- [x] `install.sh` is committed executable (`git ls-files -s install.sh` shows mode `100755`)
- [x] move this plan to `docs/plans/completed/`
- [x] single commit: all changes + plan move (no `Co-Authored-By` trailer — this repo's hook rejects it)
