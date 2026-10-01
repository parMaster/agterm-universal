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

## Automatic builds of new upstream releases

`.github/workflows/check-upstream.yml` runs daily (and on demand from the Actions tab). It looks up
upstream's latest release and does nothing if `<tag>-universal` already exists here. Otherwise it
checks whether the patch applies to that tag:

- **It applies** — dispatches "Build universal agterm" for that tag, which publishes the release as
  usual. If that build fails, it opens an issue titled `Universal build failed for upstream <tag>`.
- **It doesn't apply** — opens an issue titled `Patch does not apply to upstream <tag>` with the
  `git apply` output. See [below](#when-a-build-fails-at-apply-universal-build-patch) for the fix.

Each issue is opened once per tag. While a build-failure issue is open, the daily check won't retry
the build; close the issue to let it try again. An auto-build doesn't move the pinned `agterm_ref`
default; bump it yourself when convenient.

GitHub disables scheduled workflows after 60 days with no repo activity. If upstream goes quiet
long enough for that to happen, re-enable the workflow from the Actions tab.

## Installing (or updating) a build

One command, the same on Apple Silicon and Intel Macs. It needs only `curl`, so it works on a fresh
Mac without a clone of this repo:

```bash
curl -fsSL https://raw.githubusercontent.com/parMaster/agterm-universal/main/install.sh | bash
```

That installs the latest release. To install a specific one, pass its tag (with or without the
`-universal` suffix):

```bash
curl -fsSL https://raw.githubusercontent.com/parMaster/agterm-universal/main/install.sh | bash -s -- v0.33.1
```

From a clone, `./install.sh [tag]` does the same. What it does, in order:

1. Downloads the release zip into a temporary directory and checks that the app inside is universal
   (`arm64` and `x86_64`). Nothing installed is touched before this passes, so a failed download or
   a wrong tag leaves the current install as it was.
2. If a Homebrew-managed `agterm` cask is installed, removes it with a plain
   `brew uninstall --cask agterm`. **Never run that with `--zap`** — it also deletes the live app's
   state and control-socket directory (`~/Library/Application Support/agterm`), which breaks a
   currently-running instance's control socket.
3. Replaces `/Applications/agterm.app` and strips the quarantine attribute, so Gatekeeper doesn't
   block the ad-hoc-signed (non-notarized) app.
4. Links `agtermctl` into `$(brew --prefix)/bin` — `/opt/homebrew` on Apple Silicon, `/usr/local` on
   Intel Macs. Without Homebrew it skips this and prints the `ln -sf` line to run yourself.
5. Prints the installed architectures and signature, and checks that `agtermctl` runs.

**If you're replacing an agterm that's currently running**, the script only touches files on disk —
it never quits or relaunches anything, and replacing files under a running app's bundle doesn't kill
it on macOS. Quit and reopen the app yourself whenever it's convenient.

If Gatekeeper still complains, right-click (Control-click) `agterm.app` → Open, and confirm at the
prompt — this is the manual equivalent of stripping quarantine.

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
6. Commit both changes together and re-dispatch the workflow. If an auto-opened issue tracked this,
   close it once the release is published.

## Re-running a tag you already built

Re-dispatching for a tag that already has a release just replaces it — the workflow deletes the old
`<tag>-universal` release and tag before creating a fresh one.
