# Seal agterm-server checksums into the universal app

**Goal:** `agtermctl server install HOST` works from our universal build, as it does from upstream's DMG.

**Kind of change:** feature

## Intent

From v0.42.0 on, `agtermctl server install` refuses to run unless the app carries
`Contents/Resources/agterm-server.sha256`. Upstream's `scripts/release.sh` writes that file after `xcodebuild`
and re-seals the app. Our workflow runs `scripts/build.sh` instead, so our app has no such file and the
install fails with "this agtermctl is not inside a release agterm.app". This adds a workflow step that
writes the file from upstream's published server tarballs and re-seals the app.

```
before: build.sh → verify archs → package → publish zip
after:  build.sh → fetch tarballs + seal checksums → verify archs → package → publish zip + 2 tarballs
```

## Decisions

- **Hash upstream's published tarballs, not tarballs we build** — `server install` downloads from
  `github.com/umputun/agterm/releases/download/v<version>/` and compares against the bundled sum, so only
  upstream's exact bytes match. Building them ourselves would need Docker on the runner and would not
  produce the same bytes.
- **A workflow step, not a change to `universal-build.patch`** — the patch only touches what `build.sh` runs;
  the checksums depend on upstream's release assets, which exist only in CI. Keeping it out of the patch
  also keeps the patch-regeneration recipe unchanged.
- **Fail when the upstream release has no server tarballs** — every release from v0.42.0 on ships them, and
  older tags are already built and published here, so nobody rebuilds them. A missing tarball means something
  is wrong upstream, and a build without the checksum file would ship a broken `server install`.
- **Mirror upstream's release shape** — our release carries the two server tarballs beside the universal zip,
  the same files upstream publishes. `server install` still downloads from upstream, so they're a mirror
  for manual installs, not a dependency.
- **Ad-hoc re-seal the app only, the way `release.sh` does on its unsigned path** — the helpers are untouched,
  so they need no re-sign.

## Constraints / out of scope

- The job already takes ~30 of its 60 minutes. The new step adds seconds, not minutes, and gets its own
  `timeout-minutes: 5` so a stalled download fails fast instead of eating the job's budget.
- `install.sh` and the release asset name stay as they are.
- No Linux server packaging, no Docker on the runner.
- Not testing `server install` against a host in CI; that's a manual check below.

## Traps

- The checksum file format is strict: every non-empty line must be `<64 hex><two spaces><asset name>`, or
  `server install` refuses the whole file (`ServerInstall.checksum` in `agtermCore/Sources/agtermCore/ServerInstall.swift`).
  Run `shasum -a 256` from the tarballs' own directory so the names have no path prefix.
- The asset name is `agterm-server-<version>-linux-<arch>.tar.gz`, with version from the app's Info.plist
  (`AppIdentity.installed`), without the `v`. `build.sh` sets `MARKETING_VERSION` from `git describe`,
  so it already matches upstream's.
- The file must be written **before** the re-seal, or `codesign --verify --deep --strict` fails because a
  sealed resource was added (`release.sh`, lines after `xcodebuild`).
- The re-seal must not use `--deep`: it would stamp the app's TCC entitlements onto `agtermctl`, `zmx` and
  `agterm-session-host` (`release.sh` comment above its signing block). Entitlements come from
  `agterm-src/agterm/agterm.entitlements`.
- The `gh` CLI in the step needs `GH_TOKEN`, even for a public upstream repo.

## Definition of Done

- [x] A v0.42.0 build's app contains `Contents/Resources/agterm-server.sha256` with two lines, one per arch,
      matching the sums of upstream's v0.42.0 tarballs — proof: the step's log prints the file, compared with
      `shasum -a 256` of the two tarballs downloaded by hand.
- [x] The re-sealed app passes `codesign --verify --deep --strict` — proof: the step runs it and the run is green.
- [x] The helpers carry no entitlements after the re-seal — proof: the step checks
      `codesign -d --entitlements -` on each helper, as `release.sh` does.
- [x] The build fails at this step when the upstream release lacks either tarball — proof: the step exits
      non-zero with an `::error::` naming the missing asset (read the step's script; no older-tag run needed).
- ➕ [x] The sealed app's `agtermctl server install` gets past the checksum-file check, while the unsealed
      published app refuses — proof: both run locally against a fake host.
- [ ] The new step takes under a minute and the whole run stays near ~36 minutes, today's v0.42.0 time
      (up from ~30 because of upstream's new setup tests) — proof: step and job durations in `gh run view`
      (checked on the rerun after commit).
- [ ] The `v0.42.0-universal` release lists the zip and both `agterm-server-0.42.0-linux-*.tar.gz` files —
      proof: `gh release view v0.42.0-universal` (checked on the rerun after commit).
- [x] README says the release mirrors upstream's server tarballs and that `server install` works from the
      build; the "Override `agterm_ref` to re-run a past release" wording says it only works from v0.42.0 on —
      proof: read it.

## Wrap-up

- [x] No test suite or linter in this repo; `actionlint` is not installed, the YAML parses
- [x] README.md updated
- [x] move this plan to `docs/plans/completed/`
- [x] single commit: all changes + plan move

## Post-Completion

- On the Intel MBP: install the new build with `install.sh`, then run `agtermctl server install <linux-host>`
  and open the host with File ▸ Open Remote Window. The host needs systemd with a user manager.
- Close issue #5 once the v0.42.0-universal release is published.
