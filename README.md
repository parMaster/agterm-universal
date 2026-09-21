# agterm-universal

Unofficial universal (arm64+x86_64) builds of [umputun/agterm](https://github.com/umputun/agterm),
so it runs on Intel Macs too. Upstream ships arm64-only.

This repo carries no copy of agterm's source — only a small patch
(`patches/universal-build.patch`) and a GitHub Actions workflow. Every build clones
`umputun/agterm` fresh at a chosen tag, applies the patch, and runs upstream's own
`scripts/build.sh` unmodified.

## Getting a build

Go to Actions → "Build universal agterm" → "Run workflow". Leave the `agterm_ref` input empty to
build the latest upstream release, or give it a specific tag (e.g. `v0.30.0`) to build an older one.
When it finishes, the build is attached as a release in this repo's Releases tab, tagged
`<upstream-tag>-universal`.

## Running it on an Intel Mac

The app is ad-hoc signed (same as upstream's own dev builds), not notarized, and downloaded from
the internet, so Gatekeeper will refuse to open it normally. After unzipping, either:

- right-click (or Control-click) `agterm.app` → Open, and confirm at the prompt, or
- clear the quarantine attribute from Terminal: `xattr -cr /path/to/agterm.app`

## When a build fails at "Apply universal-build patch"

This means upstream changed `project.yml` or `scripts/setup.sh` in a way that no longer matches the
patch's context lines — expected occasionally, since agterm's build scripts change fairly often
(they gained a new bundled tool and bumped their zig version in the ~6 weeks after this patch was
first written). To fix:

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
   Silence and a `0` exit code mean it applies cleanly. Commit and re-dispatch the workflow.

## Re-running a tag you already built

Re-dispatching for a tag that already has a release just replaces it — the workflow deletes the old
`<tag>-universal` release and tag before creating a fresh one.
