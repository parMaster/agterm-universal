# agterm-universal

Unofficial universal (arm64+x86_64) builds of [umputun/agterm](https://github.com/umputun/agterm),
so it runs on Intel Macs too. Upstream ships arm64-only.

This repo carries no copy of agterm's source — only a small patch
(`patches/universal-build.patch`) and a GitHub Actions workflow. Every build clones
`umputun/agterm` fresh at a chosen tag, applies the patch, and runs upstream's own
`scripts/build.sh` unmodified.

## Getting a build

Go to Actions → "Build universal agterm" → "Run workflow". The `agterm_ref` input defaults to the
tag `patches/universal-build.patch` is currently verified against — leave it as-is for a normal
build. Override it to re-run a specific past release, or to try a newer upstream tag before its
patch has been regenerated (may fail at "Apply universal-build patch" — see below, and note that
requesting an *older* tag than the pinned one can fail there too). When it finishes, the build is
attached as a release in this repo's Releases tab, tagged `<upstream-tag>-universal`.

## Installing (or updating) a build

These steps work the same on Apple Silicon and Intel Macs; the only per-machine detail is the
Homebrew prefix in step 5, which the commands below resolve automatically rather than hardcode.

1. If a Homebrew-managed `agterm` cask is installed and you want this build to replace it instead,
   remove just the app and its `agtermctl` symlink. **Never pass `--zap`** — that also deletes the
   live app's state and control-socket directory (`~/Library/Application Support/agterm`), which
   breaks a currently-running instance's control socket:

   ```bash
   brew list --cask agterm >/dev/null 2>&1 && brew uninstall --cask agterm
   ```

   If agterm isn't installed via Homebrew at all (e.g. this is a fresh Mac), this is a no-op — skip
   straight to step 2.

2. Download the release you want. Empty/omitted tag = the newest one:

   ```bash
   tag="$(gh release list --repo parMaster/agterm-universal --limit 1 --json tagName --jq '.[0].tagName')"
   rm -rf /tmp/agterm-install && mkdir -p /tmp/agterm-install
   gh release download "$tag" --repo parMaster/agterm-universal --pattern '*.zip' --dir /tmp/agterm-install --clobber
   ```

   No `gh` CLI, or not authenticated? Download the `.zip` asset by hand from
   <https://github.com/parMaster/agterm-universal/releases/latest> instead — a browser download sets
   a `com.apple.quarantine` attribute that step 4 below removes; a `gh release download` does not set
   one, so step 4 is then a no-op safety net rather than a required step.

3. Unzip and move it into place (this overwrites any existing `/Applications/agterm.app`, but does
   **not** touch a process already running from the old one — deleting/replacing files under a
   running app's bundle doesn't kill it on macOS):

   ```bash
   cd /tmp/agterm-install
   unzip -q ./*.zip
   rm -rf /Applications/agterm.app
   mv agterm.app /Applications/agterm.app
   ```

4. Strip quarantine so Gatekeeper doesn't block the ad-hoc-signed (non-notarized) app:

   ```bash
   xattr -cr /Applications/agterm.app
   ```

5. Put `agtermctl` on `PATH` the same way the Homebrew cask used to, but resolve the Homebrew prefix
   instead of hardcoding it — it's `/opt/homebrew` on Apple Silicon and `/usr/local` on Intel Macs:

   ```bash
   ln -sf /Applications/agterm.app/Contents/MacOS/agtermctl "$(brew --prefix)/bin/agtermctl"
   ```

6. Verify before opening it:

   ```bash
   lipo -archs /Applications/agterm.app/Contents/MacOS/agterm   # expect: x86_64 arm64
   codesign -dv /Applications/agterm.app                         # ad-hoc signed, TeamIdentifier=not set
   agtermctl --help                                              # confirms the PATH symlink works
   ```

7. **If you're replacing an agterm that's currently running** (as opposed to a fresh install with
   nothing running yet), steps 1-6 only ever touched files on disk — they never quit or relaunched
   anything. Deciding when to quit and reopen the running app is the person's call, not an automated
   one; do that last, by hand, whenever it's convenient.

If Gatekeeper still complains after step 4 (e.g. you skipped it and downloaded via browser instead),
right-click (Control-click) `agterm.app` → Open, and confirm at the prompt — this is the manual
equivalent of stripping quarantine.

## When a build fails at "Apply universal-build patch"

This means the tag you're building has a `project.yml`/`scripts/setup.sh` shape that no longer
matches the patch's context lines — expected occasionally, since agterm's build scripts change
fairly often (they gained a new bundled tool and bumped their zig version in the ~6 weeks after
this patch was first written). It cuts both ways: a tag *older* than the one the patch was last
generated against can fail here too, not just a newer one — the patch is tied to one point in
upstream's history, not to "this tag and everything after it." To fix:

1. Clone the failing tag fresh: `git clone --branch <tag> --depth 1 https://github.com/umputun/agterm /tmp/agterm-src`
2. Re-apply the same intent by hand in `/tmp/agterm-src`:
   - `project.yml`: `ARCHS: arm64` → `ARCHS: arm64 x86_64`, and add `--arch arm64 --arch x86_64` to
     the post-build script's `swift build`/`--show-bin-path` invocations for `agtermctl` and
     `agterm-session-host`.
   - `scripts/setup.sh`: change GhosttyKit's `-Dxcframework-target=native` to `universal`, fold that
     choice into the rebuild-stamp check so switching back forces a rebuild, and build zmx twice —
     once with `-Dtarget=aarch64-macos.14.0`, once with `-Dtarget=x86_64-macos.14.0`, each with its
     own `--prefix` — then combine the two with `lipo -create` instead of the single `install`.
3. Regenerate the patch: `cd /tmp/agterm-src && git diff -- project.yml scripts/setup.sh > /path/to/agterm-universal/patches/universal-build.patch`
4. Verify it applies cleanly to a second, untouched clone of the same tag before committing:
   ```bash
   git clone --branch <tag> --depth 1 https://github.com/umputun/agterm /tmp/agterm-verify
   git -C /tmp/agterm-verify apply --check /path/to/agterm-universal/patches/universal-build.patch
   rm -rf /tmp/agterm-verify
   ```
   Silence and a `0` exit code mean it applies cleanly.
5. Bump the `agterm_ref` input's `default` in `.github/workflows/build-universal.yml` to `<tag>`,
   so the next build without an explicit override targets the tag this patch was just verified
   against.
6. Commit both changes together and re-dispatch the workflow.

## Re-running a tag you already built

Re-dispatching for a tag that already has a release just replaces it — the workflow deletes the old
`<tag>-universal` release and tag before creating a fresh one.
