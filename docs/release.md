# Release

How a build reaches a user. The local development loop is in [development.md](development.md);
the signing identity itself is in [signing.md](signing.md).

> **Delores note.** This document describes the inherited Tinycast release lane. Delores has no
> public release channel and must not consume Tinycast's feed, Homebrew casks or signing identity;
> the Delores rules live in [delores-release.md](delores-release.md). The continuous-integration
> section below `does` describe this tree's workflow, since Delores owns `.github/workflows/ci.yml`.

## Packaging a DMG locally

```sh
./Scripts/build-dmg.sh            # -> build/Tinycast-<version>.dmg (version from project.yml)
./Scripts/build-dmg.sh 0.5.7      # -> build/Tinycast-0.5.7.dmg
```

It builds a Release `Tinycast.app` signed with `Tinycast Self-Signed` and packs it with an
`/Applications` symlink. Official per-channel releases are built by CI, below.

## Signing & Gatekeeper

Both local builds and CI releases sign with the same stable `Tinycast Self-Signed` identity, not an
Apple Developer ID — so macOS quarantines a directly-downloaded DMG. The Homebrew cask strips that
automatically; direct downloaders run `xattr -dr com.apple.quarantine "…/Tinycast.app"` once. Full
details in [signing.md](signing.md).

## What a release publishes

Every release publishes two assets from one build: `Tinycast-<version>.dmg`, which people download by
hand and which a cask can install, and `Tinycast-<version>.zip` for GitHub Releases. The
zip is produced with `ditto -c -k --keepParent --sequesterRsrc` so the code signature stays verifiable.

A stable release publishes two more from the `universal` job, `Tinycast-Universal-<version>.dmg` and
`.zip`, built from the same commit at the same version and bundle id but with both slices. They are
uploaded *after* the thin pair, which keeps the thin zip first in the asset list so builds predating
architecture-aware selection keep choosing it.

Three things a release must keep true:

- **It carries a `.zip` asset this Mac can run.** A DMG-only release is not installable and is not
  offered, and an Intel build is offered nothing rather than a thin arm64 zip.
- **The tag parses as `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH-beta.N`,** and agrees with the
  `prerelease` flag. `v0.9.7-sequoia` deliberately parses as neither, which is what keeps beta
  installs off the macOS 15 build.
- **It is not a draft.**

There is no in-app updater in the current app. A Homebrew cask for Delores must not set
`auto_updates true`: that flag told Homebrew the app replaced itself, so `brew upgrade` skipped it.
Without an updater, Homebrew should be allowed to replace the app. This tree does not own the
`abue-ammar/homebrew-tinycast` tap, and must not flip that flag on Tinycast's casks.

## Continuous integration

`.github/workflows/ci.yml` is the merge gate, on a `macos-26` runner with Xcode 26 (the same selection
step as the release workflow). One job; a new push cancels the in-flight run for the same ref. It runs
on pull requests, on pushes to `integration/delores` — the default branch, which is developed by
pushing straight to it — and on demand, so the ref CI exists to protect is one it actually sees. The
checks go through the scripts below rather than naming rules or harnesses in the workflow, so none of
them can drift:

- **the harnesses** — `./Scripts/run-tests.sh`, `./Scripts/run-delores-tests.sh`, and
  `./Tests/upstream-drift-test.sh`. The vendored Huaci harness skips itself where the runner's SDK is
  below 27, because that snapshot uses a macOS 27 member no earlier SDK declares.
- **the app target** — an unsigned `Debug` build of the `Delores` scheme, with
  `CODE_SIGNING_ALLOWED=NO` and no entitlements. **This is the one check nothing else covers.** Every
  harness compiles a *subset* of the shipped sources, so target membership, a missing resource, a
  macro that only expands under the app's flags and a broken generated project are all invisible to a
  green harness run; the build is the only step that compiles what a user runs. It is deliberately
  unsigned and Debug — it proves the target compiles, and nothing in CI ships.
- **lint** — `./Scripts/lint.sh`, with `SWIFTLINT_REPORTER=github-actions-logging` so every violation
  is annotated **inline on the PR diff** instead of being buried in the log. It runs under
  `if: always()`, so a failing harness still surfaces the lint annotations in the same run. Warnings
  annotate only; **lint errors fail the job**, exactly as a local run does.

[delores-verification.md](delores-verification.md) records what each of these last said on the Delores
machine, including why one of them cannot run there.

## Releasing

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions, no local machine
needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **channel** — `beta` or `stable`. Each builds a distinct app (`Tinycast Beta.app` / `Tinycast.app`)
  with its own bundle id, alongside the local `Tinycast Dev.app`. Beta gets an auto-incrementing
  `-beta.N` suffix (`N` = the Actions run number) so re-running never collides; stable ships the
  version as-is.
- **version** — base semver, e.g. `0.2.0`.

It builds on a `macos-26` runner with Xcode 26 and publishes a GitHub Release tagged
`v<full-version>` with a versioned DMG and zip asset, marked prerelease for beta. On success it also
bumps the matching cask in the tap and announces the release on Discord.

A stable run then fans out to a second job, `universal`, which rebuilds the same commit with
`ARCHS="arm64 x86_64"` and attaches `Tinycast-Universal-<version>.dmg` / `.zip` to the release the
first job created, then bumps `tinycast-universal`. macOS 26 is the last release that boots on Intel,
and those Macs need both slices. Both jobs pin `ARCHS` explicitly and assert the slices on *every*
shipping binary: trusting `ARCHS_STANDARD` is what shipped a thin arm64 build to Intel users once
already, and it also keeps the Apple silicon download from silently gaining a slice it never needs.

### Release notes

`Scripts/release-notes.sh` composes the release body, and CI runs it just before `gh release create`.
It is safe to run by hand against any tag — it only reads:

```sh
CHANNEL=beta TAG=v0.9.13-beta.61 ./Scripts/release-notes.sh /tmp/body.md /tmp/discord.md
```

The changelog itself comes from GitHub's own release-notes API, which lists every merged PR with its
author and number — so contributors are credited without anyone maintaining a `CHANGELOG.md`, and
without Conventional Commits. **Nothing is ever committed to this repo**: the tag is created
server-side by `gh release create`, and no release, bot or version-bump commit exists.

Two details the script exists for:

- **The previous tag is picked per channel.** Beta and stable tags interleave on `main` — the same
  commit can carry both — so "the previous release" is only ever right within one channel. A stable
  release therefore spans every beta since the last stable.
- **The body is split by `<!-- tinycast:install -->`.** Everything above it is the changelog;
  everything below is the Homebrew and quarantine text, which only a download page needs. Full PR URLs are
  shortened to `#304`, which still autolinks on the web.

The Discord announcement carries the same changelog, truncated to fit Discord's component limit, and
pings `@everyone`.

### Homebrew tap automation

Each job's final step rewrites the `version` + `sha256` of its cask (`tinycast`, `tinycast@beta` or
`tinycast-universal`) in the [`homebrew-tinycast`](https://github.com/abue-ammar/homebrew-tinycast) tap
and pushes. It needs a `HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT with **Contents:
read/write** on the tap repo. Without the secret the step logs a warning and skips; the release still
publishes. The `sed` is anchored to `^  version` / `^  sha256`, so a cask's two-space indent on those
lines is load-bearing.

The three macOS 26 / macOS 15 casks all install `Tinycast.app` under `com.tinycast.app`, so they
`conflicts_with` one another and Homebrew routes each Mac by `depends_on`: `tinycast` requires
`arch: :arm64`, `tinycast-universal` takes the Intel Macs, and `tinycast-sequoia` covers macOS 15.

## Website

`.github/workflows/website.yml` builds `website/` (Next.js static export + Tailwind, with Fumadocs for
the docs section) and deploys it to GitHub Pages at `https://abue-ammar.github.io/tinycast/` on every
push to `main` that touches `website/`. Enable it once via
**Settings → Pages → Source = GitHub Actions**.

```sh
cd website && npm install && npm run dev     # local preview
```

The workflow uploads `website/out` — a Next.js export lands there, not in `dist/`. `public/.nojekyll`
must stay: GitHub Pages runs Jekyll, which ignores `_`-prefixed directories, so without it every
asset under `_next/` 404s. See [website/README.md](../website/README.md).
