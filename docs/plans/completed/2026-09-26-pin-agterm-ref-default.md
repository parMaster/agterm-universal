# Pin agterm_ref default to a known-good tag

**Goal:** Stop the `build-universal.yml` workflow from resolving an empty `agterm_ref` input to
whatever upstream's newest release happens to be at dispatch time, and instead default it to the
exact tag `patches/universal-build.patch` is currently verified against — so the no-input path
never races ahead of patch maintenance. Keep the input itself, for re-running a past release or
opportunistically trying a newer tag before its patch is regenerated. Document in README that this
default must move in the same commit as each patch regen, and that requesting any other tag can
fail "Apply universal-build patch" in either direction (older or newer than the pinned tag), not
just newer.

**Architecture:** No new files, no new concepts — this narrows one workflow input's default and
deletes the dynamic "latest release" lookup it used to fall back to, then updates the two README
passages that describe that behavior.

**Tech Stack:** GitHub Actions (`workflow_dispatch` inputs, expression syntax), Bash, `gh` CLI (for
verification only).

---

## Context (from discovery)

- This session already regenerated `patches/universal-build.patch` against upstream `v0.32.0` and
  confirmed it (committed as `5a83e10`, pushed to `main`). A workflow run dispatched with an empty
  `agterm_ref` resolved to `v0.32.0` via the current `gh api repos/umputun/agterm/releases/latest`
  lookup and got past "Apply universal-build patch" — that run is what surfaced this issue.
- Separately confirmed in this session: applying the current (v0.32.0-targeted) patch against a
  fresh `v0.29.0` checkout fails clean (`git apply --check` rejects at `scripts/setup.sh:21`) — the
  patch is tied to one point in upstream's file history, not to "this tag and everything after it."
  This is the same failure mode the README already documents for *newer* tags, just triggered from
  the other direction.
- `.github/workflows/build-universal.yml` (read in full this session) currently has:
  ```yaml
  on:
    workflow_dispatch:
      inputs:
        agterm_ref:
          description: >-
            umputun/agterm tag to build (e.g. v0.31.0). Leave empty to use
            upstream's latest release.
          required: false
          default: ""
  ```
  and a "Resolve target tag" step:
  ```yaml
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
  ```
  `GH_TOKEN` here is only used by the `gh api ... releases/latest` call being removed; the
  `GH_TOKEN` env on the later "Publish release" step is separate (`gh release delete`/`create`) and
  is untouched by this plan.
- `README.md` (read in full this session) has two passages that describe the old "empty = latest"
  behavior: the "Getting a build" section (line 13-14) and the "When a build fails at 'Apply
  universal-build patch'" section, whose numbered fix-it steps end at "Commit and re-dispatch the
  workflow" with no mention of the workflow file itself needing a companion edit.
- `grep -rn "agterm_ref\|releases/latest"` across the repo confirms no other file references this
  behavior (the `releases/latest` hit in README's install instructions is an unrelated URL to this
  repo's own release page, not upstream's — left alone).
- No Go/test tooling applies to this repo (no `go.mod`, no Makefile, no CI test step) — it's a
  workflow YAML file plus a patch plus docs. "Testing" here means: local syntax validation, then one
  real `workflow_dispatch` run watched just far enough to confirm the resolve step's behavior, then
  cancelled (a full build is ~15-20 min and irrelevant to what this change touches).
- Neither `actionlint` nor `yamllint` is installed locally (checked this session) — plan uses
  `python3 -c "import yaml; yaml.safe_load(...)"` for basic syntax validation instead of asking to
  install new tooling for a one-file change.

## Verified Dependency Behaviors

- `workflow_dispatch` input defaults (GitHub REST API docs, "Create a workflow dispatch event",
  checked this session via WebFetch): "Any default properties configured in the workflow file will
  be used when inputs are omitted." This is the exact mechanism Task 1 relies on — it applies to any
  dispatch that omits `agterm_ref` from its request body, which covers the web UI's default dispatch
  (nothing typed), `gh workflow run` with no `-f agterm_ref=...`, and a raw API call that leaves the
  key out. It is what makes the input's `default:` field a safe single source of truth, with no
  bash-level fallback needed in the "Resolve target tag" step.

## Development Approach

- **testing approach**: Regular — no unit-testable logic, only workflow YAML + Bash + docs. Verified
  by YAML syntax parse, then one real dispatch watched at the "Resolve target tag" step only.
- **CRITICAL: verification requires the workflow file to exist on the remote first** — GitHub
  Actions can only run a `workflow_dispatch` workflow that's already on a branch in the repo. So
  Task 1-2 stage changes, Task 3 commits + pushes, Task 4 dispatches and verifies against the real
  runner (cancelling once verified, not waiting for a full build).
- **CRITICAL: single summary commit** — Tasks 1-2 stage files but do not commit; Task 3 is the one
  commit (and push) covering both.
- **CRITICAL: update this plan file when scope changes during implementation.**

## Technical Details

- **Single source of truth for the pinned tag**: the input's own `default:` field
  (`v0.32.0`). The "Resolve target tag" step no longer needs a bash-level fallback or an API call —
  `workflow_dispatch` applies an input's schema `default` whenever the dispatch payload omits that
  input, for both the GitHub UI ("Run workflow" pre-fills the text box with the default) and
  API/`gh workflow run` dispatches that don't pass `agterm_ref` explicitly. The step becomes a
  straight passthrough: read `inputs.agterm_ref`, log it, publish it as the step output.
- **What "empty" means changes**: previously, an empty string meant "ask GitHub for upstream's
  newest release." Now, in normal use the field is never actually empty — dispatching without
  touching it sends the pre-filled default. A user who explicitly clears the text field before
  submitting will send a real empty string, which reaches `git clone --branch "" ...` at the
  "Checkout umputun/agterm" step and fails there with an unambiguous git error — an edge case
  reachable only by deliberately erasing a pre-filled field, not by normal use, so no extra handling
  is added for it.
- **Bump discipline**: every time `patches/universal-build.patch` is regenerated for a new upstream
  tag (per the README's existing "When a build fails" steps), the `default:` on `agterm_ref` must
  move to that same tag in the same commit. This plan adds that as an explicit numbered step in
  README's fix-it section, replacing its old closing "Commit and re-dispatch" step.

## Implementation Steps

### Task 1: Pin the workflow's default and drop the "latest" lookup

**Files:**
- Modify: `.github/workflows/build-universal.yml`

- [ ] Update the `agterm_ref` input's description and default:

```yaml
      agterm_ref:
        description: >-
          umputun/agterm tag to build. Defaults to the tag
          patches/universal-build.patch is currently verified against — bump this
          default in the same commit as each patch regen (see README). Override to
          re-run a past release, or to try a newer upstream tag before its patch has
          been regenerated.
        required: false
        default: "v0.32.0"
```

- [ ] Simplify the "Resolve target tag" step to a passthrough, dropping the `GH_TOKEN` env and the
      `releases/latest` API call:

```yaml
      - name: Resolve target tag
        id: resolve
        run: |
          set -euo pipefail
          ref="${{ inputs.agterm_ref }}"
          echo "using upstream ref: $ref"
          echo "ref=$ref" >> "$GITHUB_OUTPUT"
```

- [ ] Validate YAML syntax locally:

  Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-universal.yml'))" && echo OK`
  Expected: `OK`

- [ ] Confirm no other step in the file still references the removed `gh api` call or depends on the
      old empty-check:

  Run: `grep -n "releases/latest\|GH_TOKEN" .github/workflows/build-universal.yml`
  Expected: only the "Resolve target tag" job's `env:` line is gone; the `GH_TOKEN` line under
  "Publish release" (further down, for `gh release delete`/`create`) is still present untouched.

### Task 2: Update README for the new default behavior

**Files:**
- Modify: `README.md`

- [ ] In "Getting a build", replace the old "leave empty for latest" line:

  Old:
  ```markdown
  Go to Actions → "Build universal agterm" → "Run workflow". Leave the `agterm_ref` input empty to
  build the latest upstream release, or give it a specific tag (e.g. `v0.30.0`) to build an older one.
  When it finishes, the build is attached as a release in this repo's Releases tab, tagged
  `<upstream-tag>-universal`.
  ```

  New:
  ```markdown
  Go to Actions → "Build universal agterm" → "Run workflow". The `agterm_ref` input defaults to the
  tag `patches/universal-build.patch` is currently verified against — leave it as-is for a normal
  build. Override it to re-run a specific past release, or to try a newer upstream tag before its
  patch has been regenerated (may fail at "Apply universal-build patch" — see below, and note that
  requesting an *older* tag than the pinned one can fail there too). When it finishes, the build is
  attached as a release in this repo's Releases tab, tagged `<upstream-tag>-universal`.
  ```

- [ ] In "When a build fails at 'Apply universal-build patch'", add the both-directions note and
      replace the closing step with two steps that also bump the workflow's pinned default:

  Old opening paragraph:
  ```markdown
  This means upstream changed `project.yml` or `scripts/setup.sh` in a way that no longer matches the
  patch's context lines — expected occasionally, since agterm's build scripts change fairly often
  (they gained a new bundled tool and bumped their zig version in the ~6 weeks after this patch was
  first written). To fix:
  ```

  New opening paragraph:
  ```markdown
  This means the tag you're building has a `project.yml`/`scripts/setup.sh` shape that no longer
  matches the patch's context lines — expected occasionally, since agterm's build scripts change
  fairly often (they gained a new bundled tool and bumped their zig version in the ~6 weeks after
  this patch was first written). It cuts both ways: a tag *older* than the one the patch was last
  generated against can fail here too, not just a newer one — the patch is tied to one point in
  upstream's history, not to "this tag and everything after it." To fix:
  ```

  Old closing step (step 4, includes the verify block and ends with "Commit and re-dispatch the
  workflow."):
  ```markdown
  4. Verify it applies cleanly to a second, untouched clone of the same tag before committing:
     ```bash
     git clone --branch <tag> --depth 1 https://github.com/umputun/agterm /tmp/agterm-verify
     git -C /tmp/agterm-verify apply --check /path/to/agterm-universal/patches/universal-build.patch
     rm -rf /tmp/agterm-verify
     ```
     Silence and a `0` exit code mean it applies cleanly. Commit and re-dispatch the workflow.
  ```

  New closing steps (step 4 trimmed to just the verify block, plus new steps 5-6):
  ```markdown
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
  ```

- [ ] Confirm the edits landed and no stale reference to the old behavior remains:

  Run: `grep -n "latest upstream release\|Commit and re-dispatch the workflow\." README.md`
  Expected: no output (both phrasings were replaced).

### Task 3: Commit and push

- [ ] Stage both files:

  Run: `git add .github/workflows/build-universal.yml README.md`

- [ ] Review the staged diff for anything unexpected before committing:

  Run: `git diff --cached`
  Expected: only the hunks described in Tasks 1-2.

- [ ] Commit (no attribution trailer — this repo's local hook rejects `Co-Authored-By` lines):

  Run: `git commit -m "Pin agterm_ref default instead of resolving upstream's latest release" -m "Empty used to mean \"ask GitHub for umputun/agterm's newest release,\" which could race ahead of patches/universal-build.patch before it's been regenerated for that release. Default now pins to the exact tag the patch is currently verified against (bumped alongside each regen); the input itself stays, for re-running a past release or trying a newer tag early. README's troubleshooting steps now also cover the older-tag direction and the default-bump step."`

- [ ] Push:

  Run: `git push origin main`

### Task 4: Verify against a real dispatch, then wrap up

- [ ] Dispatch the workflow with no `agterm_ref` override, confirming the default fills in:

  Run: `gh workflow run build-universal.yml --repo parMaster/agterm-universal`

  This sends no `-f agterm_ref=...`, so GitHub applies the input's schema default (`v0.32.0`).

- [ ] Find the new run, then poll until its "Resolve target tag" step finishes:

  Run:
  ```bash
  sleep 5
  run_id="$(gh run list --repo parMaster/agterm-universal --workflow build-universal.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
  echo "run: $run_id"
  while :; do
    conclusion="$(gh run view "$run_id" --repo parMaster/agterm-universal --json jobs \
      --jq '.jobs[0].steps[] | select(.name=="Resolve target tag") | .conclusion')"
    [ -n "$conclusion" ] && break
    sleep 5
  done
  echo "resolve step: $conclusion"
  ```
  Expected: `resolve step: success`

- [ ] Confirm the step's log shows the pinned tag with no API call involved:

  Run:
  ```bash
  job_id="$(gh run view "$run_id" --repo parMaster/agterm-universal --json jobs --jq '.jobs[0].databaseId')"
  gh run view "$run_id" --repo parMaster/agterm-universal --log --job "$job_id" | grep "using upstream ref:"
  ```
  Expected: `...Resolve target tag	using upstream ref: v0.32.0`

- [ ] Cancel the run — the resolve step is what this change touches; the rest of the build is
      already covered by the earlier v0.32.0 verification run from this session, so there's no need
      to burn another ~15-20 minutes of runner time re-confirming it:

  Run: `gh run cancel "$run_id" --repo parMaster/agterm-universal`

### Task 5: Verify acceptance criteria and finish

- [ ] Verify all requirements from Goal are implemented: default no longer calls
      `releases/latest`, default pins to `v0.32.0`, input still overridable, README documents the
      bump discipline and the both-directions failure mode.
- [ ] Move this plan to `docs/plans/completed/`:

  Run: `mkdir -p docs/plans/completed && mv docs/plans/2026-09-26-pin-agterm-ref-default.md docs/plans/completed/`

- [ ] Task 3 already committed and pushed all implementation changes, so the move is its own small
      follow-up commit (same pattern as this repo's prior plan, `docs/plans/completed/2026-09-21-universal-build-workflow.md`, commit `18427f3`):

  Run:
  ```bash
  git add docs/plans/completed/2026-09-26-pin-agterm-ref-default.md
  git commit -m "docs: move pin-agterm-ref-default plan to completed"
  git push origin main
  ```

## Post-Completion

*Items requiring manual intervention or external systems*

- None — the pinned default (`v0.32.0`) already matches the patch currently in `main`; no further
  regen is needed as a result of this plan.
