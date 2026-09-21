# Universal (arm64+x86_64) build workflow for umputun/agterm

**Goal:** A manually-triggered GitHub Actions workflow in this repo that builds a universal
(arm64+x86_64) `agterm.app` from a tagged release of `umputun/agterm`, ad-hoc signs it (same as
upstream's own build), and publishes it as a GitHub Release in this repo.

**Architecture:** This repo carries no copy of agterm's source. It holds only a small patch file
(`patches/universal-build.patch`) and a workflow. On dispatch, the workflow resolves a target tag
(input, or upstream's latest release), checks out `umputun/agterm` fresh at that tag into a
subdirectory, applies the patch, runs upstream's own `scripts/build.sh` unmodified, verifies every
bundled binary is a fat arm64+x86_64 Mach-O, zips the app with `ditto` (preserving the code
signature), and publishes it as a release tagged `<upstream-tag>-universal`.

**Tech Stack:** GitHub Actions (`macos-26` runner, Apple Silicon), Bash, `git apply`, upstream's own
`scripts/setup.sh`/`scripts/build.sh` (Homebrew zig/xcodegen, zig, xcodebuild), `lipo`, `ditto`,
`gh` CLI.

---

## Context (from discovery)

- This repo (`agterm-universal`, `github.com/parMaster/agterm-universal`) was just created via
  `gh repo create` and cloned to `/Users/gusto/go/src/agterm-universal`. It is completely empty:
  local branch `main`, no commits, remote `origin` set to
  `git@github.com:parMaster/agterm-universal.git` (ssh).
- Upstream (`umputun/agterm`, `/Users/gusto/go/src/agterm` locally) is MIT-licensed. Latest tagged
  release is `v0.31.0` (2026-09-20), 6 commits behind current `master` (`5d3a45a`).
- Earlier in this session we hand-built a universal binary directly in the `agterm` checkout on
  `master` and confirmed every bundled binary (`agterm`, `agtermctl`, `agterm-session-host`, `zmx`)
  in the resulting `agterm.app` is a fat arm64+x86_64 Mach-O. The two files that needed changes:
  `project.yml` (`ARCHS`, and the post-build script's three `swift build`/`--show-bin-path`
  invocations for `agtermctl`/`agterm-session-host`) and `scripts/setup.sh` (GhosttyKit's
  `-Dxcframework-target` native→universal, and zmx built twice — once per arch — then `lipo`'d into
  one binary).
- Those exact edits were re-derived against a clean `v0.31.0` worktree (not `master`, since
  `setup.sh` gained an unrelated zmx-patches loop between the tag and `master` that isn't present at
  the tag) and confirmed with `git apply --check` to apply cleanly to a **fresh** `v0.31.0`
  checkout. That verified diff is the patch this plan ships.
- `umputun/agterm`'s own CI (`.github/workflows/ci.yml`) builds on `runs-on: macos-26` with
  `actions/checkout@v7` and `brew install xcodegen` before `scripts/build.sh` — this plan's workflow
  mirrors that.
- User decisions already made (this session): workflow_dispatch only (no cron polling), track
  tagged releases only (not master), ad-hoc codesign only (no Apple Developer cert / notarization).

## Verified Dependency Behaviors

- `scripts/build.sh` (`umputun/agterm`, read in full this session): runs `./scripts/setup.sh`,
  `xcodegen generate`, computes `VERSION` from `git describe --tags` (falls back to `0.0.0` if no
  tag reachable — irrelevant here since we always checkout exactly at a tag), then
  `xcodebuild ... -configuration Release build`, and prints
  `built: build/DerivedData/Build/Products/Release/agterm.app`. It does not push, sign with a real
  identity, or notarize — the app it leaves behind is ad-hoc signed by `project.yml`'s own
  post-build script (`codesign --sign -`), matching what this plan needs with no extra signing step.
- `scripts/setup.sh` (read in full, then patched and exercised locally this session): idempotent —
  skips the ghostty/zmx rebuild only when staged artifacts plus their stamp files already match: our
  patch folds the new `XCFRAMEWORK_TARGET`/wider `ZMX_TARGET` strings into those stamps, so a
  same-run rebuild always sees no stamp on a fresh checkout and does the universal build; this
  matters for this plan only in that every CI run is a full fresh build (no caching), which is fine
  at the "call it by hand" cadence the user chose.
- `gh release create <tag> <file>... --repo <owner/name>`: creates the tag if it doesn't already
  point at a commit in the target repo, uploads the given files as release assets, and fails if the
  tag already exists (whether or not it has a release attached). `gh release delete <tag> --yes
  --cleanup-tag` removes both the release and the underlying tag first, which is why the workflow
  calls it (suppressing its non-zero exit when the tag doesn't exist yet) before every `create`.
- `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name`: returns the tag name of the most
  recent non-draft, non-prerelease release — exactly umputun/agterm's newest `vX.Y.Z` tag, since that
  project's releases aren't marked draft/prerelease (confirmed via `gh release list` this session:
  `v0.31.0` shows as `Latest`).

## Development Approach

- **testing approach**: Regular — there's no unit-testable logic here, only a CI workflow. The
  workflow's own IO (does it produce a downloadable universal app) is the test, verified by actually
  dispatching it after pushing.
- **CRITICAL: verification here requires the code to exist on GitHub first** (GitHub Actions can
  only run a workflow that's already on a ref in the repo). So this plan's task order deviates from
  the usual "verify, then wrap-up-commit": implement the 3 files (Task 1-3), commit + push once
  (Task 4), then dispatch and verify against the real runner (Task 5).
- **CRITICAL: single summary commit** — Tasks 1-3 stage files but do not commit; Task 4 is the one
  commit (and push) covering all of them. If Task 5's live run surfaces a real bug, fix it and push a
  second, clearly-named commit rather than amending — don't force-push a public repo's `main`.
- no linter is configured for this repo (it's two YAML/text files and a patch); `bash -n` any
  embedded shell blocks you edit, and validate workflow YAML with `gh workflow view` after push
  (Task 5) rather than a separate lint step.

## Technical Details

- **Why a patch file instead of a fork**: already explained to and agreed by the user this session.
  Upstream's `project.yml`/`scripts/setup.sh` already changed twice in the ~6 weeks since the user's
  original ad-hoc Intel patch (zig 0.15.2→0.16, and a new bundled `zmx` tool with an arm64-only build
  step) — a patch fails `git apply` loudly and cheaply on the next such change; a real fork would
  need a full merge/rebase across agterm's entire history.
- **Why re-derive the patch against `v0.31.0` rather than reuse the `master` diff verbatim**: this
  workflow's default target is the latest tag, not `master`, and `scripts/setup.sh` differs between
  the two (the zmx-patches loop). A patch generated against `master` would fail to apply against the
  tag it actually needs to run on.
- **Tag naming**: the release this workflow creates in `agterm-universal` is tagged
  `<upstream-tag>-universal` (e.g. `v0.31.0-universal`), distinguishing it from any tag scheme
  upstream might use and making the mapping back to the exact agterm version unambiguous.
- **Idempotent re-runs**: re-dispatching for a tag that already has a published release deletes and
  recreates that release+tag rather than failing, so re-running after fixing a patch (or just wanting
  a fresh rebuild) doesn't require manual cleanup.
- **No caching, no scheduled polling, no notarization**: all deliberately out of scope per the
  user's choices this session (manual trigger, ad-hoc signing). Caching would only pay off across
  many runs; at a hand-dispatched cadence a full ~10-minute rebuild each time is an acceptable trade
  for one less moving part.

## Progress Tracking

- mark completed items with `[x]` immediately when done
- add newly discovered tasks with ➕ prefix
- document issues/blockers with ⚠️ prefix

⚠️ First live dispatch (run 35591370088) failed at "Apply universal-build patch": the step used
`git -C agterm-src apply ... patches/universal-build.patch`, but `-C agterm-src` makes git resolve
that relative path from inside `agterm-src`, not the workspace root where `patches/` actually lives
— `git apply` doesn't cd like a shell `cd` would for a plain relative path outside `-C`. Fixed by
pointing at `"$GITHUB_WORKSPACE/patches/universal-build.patch"` instead, in both the workflow file
and this plan's Task 2.

## Implementation Steps

### Task 1: Add the universal-build patch

**Files:**
- Create: `patches/universal-build.patch`

- [ ] **Write the patch file** with exactly this content (already generated and verified with
  `git apply --check` against a fresh `v0.31.0` checkout of `umputun/agterm` this session):

```diff
diff --git a/project.yml b/project.yml
index daabdde..7e60255 100644
--- a/project.yml
+++ b/project.yml
@@ -16,7 +16,7 @@ settings:
     SWIFT_VERSION: "6.0"
     SDKROOT: macosx
     MACOSX_DEPLOYMENT_TARGET: "14.0"
-    ARCHS: arm64
+    ARCHS: arm64 x86_64
     ONLY_ACTIVE_ARCH: NO
     SWIFT_STRICT_CONCURRENCY: complete
     # The agtermTests scheme intentionally builds serially so the app's deep-sign
@@ -140,9 +140,9 @@ targets:
           # otherwise trip the re-seal below.
           rm -rf "$CODESIGNING_FOLDER_PATH/Contents/Resources/AppIcon.icon"
           core="$SRCROOT/agtermCore"
-          swift build --package-path "$core" -c release --product agtermctl
-          swift build --package-path "$core" -c release --product agterm-session-host
-          src="$(swift build --package-path "$core" -c release --product agtermctl --show-bin-path)/agtermctl"
+          swift build --package-path "$core" --arch arm64 --arch x86_64 -c release --product agtermctl
+          swift build --package-path "$core" --arch arm64 --arch x86_64 -c release --product agterm-session-host
+          src="$(swift build --package-path "$core" --arch arm64 --arch x86_64 -c release --product agtermctl --show-bin-path)/agtermctl"
           host_src="$(dirname "$src")/agterm-session-host"
           cli_dest="$CODESIGNING_FOLDER_PATH/Contents/MacOS/agtermctl"
           host_dest="$CODESIGNING_FOLDER_PATH/Contents/MacOS/agterm-session-host"
diff --git a/scripts/setup.sh b/scripts/setup.sh
index 5a01f72..2d32dd4 100755
--- a/scripts/setup.sh
+++ b/scripts/setup.sh
@@ -21,14 +21,20 @@ GHOSTTY_REPO="https://github.com/ghostty-org/ghostty"
 GHOSTTY_REV="683d8db643b95cf229bfb5fe9fab9ae677920343"  # 2026-08-25
 ZMX_REPO="https://github.com/neurosnap/zmx"
 ZMX_REV="8bab1f0173b07e79835ea372d749af3dbf0d0842"  # v0.8.1, 2026-09-05
-# zig defaults to the builder's OS version and CPU; ship the app's arm64/macOS 14 baseline.
-ZMX_TARGET="aarch64-macos.14.0"
+# local patch (agterm-universal): build zmx as a universal (arm64+x86_64) binary alongside
+# GhosttyKit so agterm runs on Intel Macs too; each arch target is built separately, then lipo'd
+# together below.
+ZMX_TARGET="universal(aarch64-macos.14.0,x86_64-macos.14.0)"
 # ghostty pins minimum_zig_version 0.16.0. Name the MINOR LINE, not `zig`: that one rolls, so a fresh
 # build once 0.17 is current would compile a fixed GHOSTTY_REV with a compiler it never supported. Today
 # `zig@0.16` is still an alias for `zig`, so this buys nothing yet — it claims the name Homebrew uses when
 # it cuts the real versioned formula, as it already has for zig@0.15 and zig@0.14.
 ZIG_FORMULA="zig@0.16"  # resolved by prefix, so an unlinked keg works
 XCFRAMEWORK_DIR="GhosttyKit.xcframework"
+# local patch (agterm-universal): universal (arm64+x86_64) instead of upstream's native-only
+# default, so agterm runs on Intel Macs too. Folded into the stamp so switching back to native
+# forces a rebuild.
+XCFRAMEWORK_TARGET="universal"
 # terminfo/ is the marker: it must extract as a SIBLING of ghostty/ so libghostty's
 # TERMINFO=dirname(GHOSTTY_RESOURCES_DIR)/terminfo derivation resolves xterm-ghostty.
 RESOURCES_MARKER="agterm/Resources/terminfo"
@@ -57,7 +63,7 @@ fi
 
 # a stale stamp restages BOTH: they come out of one build, and an artifact built from another revision
 # cannot be told apart from a current one.
-if [[ ! -f "$STAMP_FILE" || "$(cat "$STAMP_FILE")" != "$GHOSTTY_REV" ]]; then
+if [[ ! -f "$STAMP_FILE" || "$(cat "$STAMP_FILE")" != "$GHOSTTY_REV $XCFRAMEWORK_TARGET" ]]; then
   need_xc=true
   need_res=true
 fi
@@ -145,7 +151,7 @@ if $need_xc || $need_res; then
 
   echo "building GhosttyKit.xcframework with zig (a few minutes)..."
   ( cd "$ghostty_build" && "$ZIG" build -Doptimize=ReleaseFast -Demit-xcframework=true \
-      -Dxcframework-target=native -Demit-macos-app=false )
+      "-Dxcframework-target=$XCFRAMEWORK_TARGET" -Demit-macos-app=false )
 
   if $need_xc; then
     echo "staging GhosttyKit.xcframework..."
@@ -161,7 +167,7 @@ if $need_xc || $need_res; then
     cp -R "$ghostty_build/zig-out/share/ghostty/themes" agterm/Resources/ghostty/
     cp -R "$ghostty_build/zig-out/share/terminfo" agterm/Resources/terminfo
   fi
-  printf '%s\n' "$GHOSTTY_REV" > "$STAMP_FILE"
+  printf '%s\n' "$GHOSTTY_REV $XCFRAMEWORK_TARGET" > "$STAMP_FILE"
 fi
 
 if $need_zmx; then
@@ -174,11 +180,14 @@ if $need_zmx; then
 
   patch_zig_float_h
 
-  echo "building zmx with zig..."
-  ( cd "$zmx_build" && "$ZIG" build -Doptimize=ReleaseSafe -Dtarget="$ZMX_TARGET" )
+  echo "building zmx with zig for arm64 and x86_64..."
+  ( cd "$zmx_build" && "$ZIG" build -Doptimize=ReleaseSafe -Dtarget=aarch64-macos.14.0 --prefix "$BUILD_DIR/zmx-arm64" )
+  ( cd "$zmx_build" && "$ZIG" build -Doptimize=ReleaseSafe -Dtarget=x86_64-macos.14.0 --prefix "$BUILD_DIR/zmx-x86_64" )
   rm -rf "$ZMX_STAGE_DIR"
   mkdir -p "$ZMX_STAGE_DIR"
-  install -m 0755 "$zmx_build/zig-out/bin/zmx" "$ZMX_STAGE_DIR/zmx"
+  lipo -create -output "$ZMX_STAGE_DIR/zmx" \
+    "$BUILD_DIR/zmx-arm64/bin/zmx" "$BUILD_DIR/zmx-x86_64/bin/zmx"
+  chmod 0755 "$ZMX_STAGE_DIR/zmx"
   cp "$zmx_build/LICENSE" "$ZMX_STAGE_DIR/LICENSE"
   printf '%s %s\n' "$ZMX_REV" "$ZMX_TARGET" > "$ZMX_STAMP_FILE"
 fi
```

- [ ] **Confirm it still applies cleanly** before moving on (belt-and-suspenders re-check; it was
  already verified this session, but re-verify against a fresh clone since the working tree used to
  generate it was a scratch worktree that no longer exists):

  ```bash
  rm -rf /tmp/agterm-patch-verify
  git clone --branch v0.31.0 --depth 1 https://github.com/umputun/agterm /tmp/agterm-patch-verify
  git -C /tmp/agterm-patch-verify apply --check /Users/gusto/go/src/agterm-universal/patches/universal-build.patch
  echo "exit code: $?"
  rm -rf /tmp/agterm-patch-verify
  ```

  Expected: `exit code: 0`, no output from `apply --check` (silence means success).

### Task 2: Add the build workflow

**Files:**
- Create: `.github/workflows/build-universal.yml`

- [ ] **Write the workflow**:

```yaml
name: Build universal agterm

on:
  workflow_dispatch:
    inputs:
      agterm_ref:
        description: >-
          umputun/agterm tag to build (e.g. v0.31.0). Leave empty to use
          upstream's latest release.
        required: false
        default: ""

permissions:
  contents: write

jobs:
  build:
    runs-on: macos-26
    timeout-minutes: 30
    steps:
      - name: Checkout this repo
        uses: actions/checkout@v7

      - name: Resolve target tag
        id: resolve
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          ref="${{ inputs.agterm_ref }}"
          if [ -z "$ref" ]; then
            ref="$(gh api repos/umputun/agterm/releases/latest --jq .tag_name)"
          fi
          echo "using upstream ref: $ref"
          echo "ref=$ref" >> "$GITHUB_OUTPUT"

      - name: Checkout umputun/agterm
        uses: actions/checkout@v7
        with:
          repository: umputun/agterm
          ref: ${{ steps.resolve.outputs.ref }}
          path: agterm-src

      - name: Apply universal-build patch
        run: |
          set -euo pipefail
          if ! git -C agterm-src apply --whitespace=nowarn "$GITHUB_WORKSPACE/patches/universal-build.patch"; then
            echo "::error::patches/universal-build.patch failed to apply against ${{ steps.resolve.outputs.ref }} — upstream likely changed project.yml or scripts/setup.sh since this patch was generated. Regenerate it (see README.md) and retry." >&2
            exit 1
          fi

      - name: Install xcodegen
        run: brew install xcodegen

      - name: Build universal agterm.app
        working-directory: agterm-src
        run: ./scripts/build.sh

      - name: Verify universal binaries
        working-directory: agterm-src
        run: |
          set -euo pipefail
          app="build/DerivedData/Build/Products/Release/agterm.app"
          for bin in agterm agtermctl agterm-session-host zmx; do
            archs="$(lipo -archs "$app/Contents/MacOS/$bin")"
            echo "$bin: $archs"
            if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
              echo "::error::$bin is not universal (archs: $archs)" >&2
              exit 1
            fi
          done

      - name: Package app
        id: package
        working-directory: agterm-src
        run: |
          set -euo pipefail
          app="build/DerivedData/Build/Products/Release/agterm.app"
          zip_name="agterm-${{ steps.resolve.outputs.ref }}-universal.zip"
          ditto -c -k --keepParent "$app" "$zip_name"
          echo "zip_path=agterm-src/$zip_name" >> "$GITHUB_OUTPUT"

      - name: Publish release
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          tag="${{ steps.resolve.outputs.ref }}-universal"
          gh release delete "$tag" --repo "${{ github.repository }}" --yes --cleanup-tag 2>/dev/null || true
          gh release create "$tag" "${{ steps.package.outputs.zip_path }}" \
            --repo "${{ github.repository }}" \
            --title "agterm ${{ steps.resolve.outputs.ref }} (universal arm64+x86_64)" \
            --notes "Unofficial universal (arm64+x86_64) build of umputun/agterm ${{ steps.resolve.outputs.ref }}, built by applying patches/universal-build.patch on top of unmodified upstream source. Ad-hoc signed, not notarized — see this repo's README before opening it."
```

- [ ] **Sanity-check the YAML** before committing:

  ```bash
  ruby -ryaml -e "YAML.load_file('.github/workflows/build-universal.yml')" && echo "YAML OK"
  ```

  Expected: `YAML OK`. This only checks the file parses as YAML — GitHub's own schema validation
  (e.g. unknown keys, bad expression syntax) only happens once it's pushed, which Task 5 covers by
  actually dispatching it.

### Task 3: Add the README

**Files:**
- Create: `README.md`

- [ ] **Write it**:

```markdown
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
```

### Task 4: Commit and push

- [ ] **Stage and commit everything** (the one summary commit for this whole plan):

  ```bash
  cd /Users/gusto/go/src/agterm-universal
  git add patches/universal-build.patch .github/workflows/build-universal.yml README.md docs/plans/2026-09-21-universal-build-workflow.md
  git status
  ```

  Expected: all four new files listed under "Changes to be committed", nothing else.

- [ ] **Commit**:

  ```bash
  git commit -m "$(cat <<'EOF'
  Add manual universal-build workflow for umputun/agterm

  Patches project.yml and scripts/setup.sh to build arm64+x86_64 instead
  of arm64-only, then publishes the ad-hoc signed app as a GitHub Release.
  EOF
  )"
  ```

- [ ] **Push**:

  ```bash
  git push -u origin main
  ```

  Expected: push succeeds (this is the first push to a brand-new empty repo, so there is nothing to
  be behind).

### Task 5: Dispatch and verify

- [ ] **Trigger a build** for the current latest release (`v0.31.0` as of this plan; re-check with
  `gh release list --repo umputun/agterm --limit 1` in case a newer one shipped by the time you run
  this):

  ```bash
  gh workflow run build-universal.yml --repo parMaster/agterm-universal
  ```

- [ ] **Watch it run**:

  ```bash
  sleep 5
  run_id="$(gh run list --repo parMaster/agterm-universal --workflow=build-universal.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
  gh run watch "$run_id" --repo parMaster/agterm-universal --exit-status
  ```

  Expected: exits 0. If it fails at "Apply universal-build patch", follow the README's regeneration
  steps, fix `patches/universal-build.patch` locally, commit
  (`git commit -m "Fix universal-build patch for <tag>"`), push, and re-run this task. If it fails at
  "Verify universal binaries", the patch applied but didn't actually produce a fat binary for the
  binary named in the error — re-check that step's edits against Task 1's diff before touching
  anything else.

- [ ] **Confirm the release**:

  ```bash
  gh release view "$(gh release list --repo parMaster/agterm-universal --limit 1 --json tagName --jq '.[0].tagName')" \
    --repo parMaster/agterm-universal
  ```

  Expected: shows a release tagged `<tag>-universal` with one `agterm-<tag>-universal.zip` asset.

- [ ] **Spot-check the artifact locally** (confirms the whole chain, not just that CI reported
  green):

  ```bash
  cd /tmp
  gh release download "$(gh release list --repo parMaster/agterm-universal --limit 1 --json tagName --jq '.[0].tagName')" \
    --repo parMaster/agterm-universal --pattern '*.zip' --clobber
  unzip -q -o agterm-*-universal.zip -d /tmp/agterm-universal-check
  lipo -archs /tmp/agterm-universal-check/agterm.app/Contents/MacOS/agterm
  rm -rf /tmp/agterm-universal-check /tmp/agterm-*-universal.zip
  ```

  Expected: `lipo -archs` prints both `x86_64` and `arm64`.

### Task 6: Wrap up

- [ ] move this plan to `docs/plans/completed/`:

  ```bash
  mkdir -p docs/plans/completed
  mv docs/plans/2026-09-21-universal-build-workflow.md docs/plans/completed/
  ```

- [ ] if Task 5 required a follow-up fix commit, that already happened as its own commit per this
  plan's Development Approach — nothing further to squash or amend.

- [ ] final commit for the plan move (the `mv` above already removed the old path from disk, so
  `git add` on both paths stages the move as a rename — one add covers the deletion and the
  addition):

  ```bash
  git add docs/plans/2026-09-21-universal-build-workflow.md docs/plans/completed/2026-09-21-universal-build-workflow.md
  git commit -m "docs: move universal-build-workflow plan to completed"
  git push
  ```

## Post-Completion

*Items requiring manual intervention or external systems*

- None currently. If umputun/agterm's build requirements change again (another zig bump, another
  bundled helper tool), the fix is always: regenerate `patches/universal-build.patch` per the
  README, no workflow changes needed.
