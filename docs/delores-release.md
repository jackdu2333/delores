# Delores packaging and release boundary

Delores has a local signed packaging path, and since 2026-09-19 a release feed of its own on
`jackdu2333/delores`: releases `v0.2.0`, `v0.2.1` and `v0.2.2`, cut by hand. What it still does not have is an
*automatic* release channel, and that separation is intentional: a Delores build must never consume
Tinycast's release feed, GitHub releases, Homebrew casks or signing identity by accident. The two
feeds are separate because the repositories are — Tinycast's releases live on `abue-ammar/tinycast`,
and `gh release list` in this checkout answers from there unless `--repo` says otherwise, which is
how a release can look like it already exists here when it does not.

## Local DMG

On a machine with Xcode 26 and the local signing identity configured:

```sh
./Scripts/build-delores-dmg.sh
./Scripts/build-delores-dmg.sh 0.2.2
```

The script uses the `Delores` scheme from `Tinycast.xcodeproj`, produces `Delores.app`, and writes
`build/Delores-<version>.dmg`. The default local identity is `HuaciGongju CodeSign`; override it for
another machine with `DELORES_CODE_SIGN_IDENTITY`.

Run it with no argument and the version is whatever `project.yml` carries — `MARKETING_VERSION` is a
real source of truth and is currently **0.2.2**. The Build is not read from there: the script derives
it as `git rev-list --count HEAD` and passes it as `CURRENT_PROJECT_VERSION`, so the DMG names the
commit it was built from ([delores-versioning.md](delores-versioning.md)). The argument overrides
`MARKETING_VERSION` for that one build, and the DMG is named from the built app's own
`CFBundleShortVersionString`, so the two can never disagree.

The script also asserts what it just built: the app's `CFBundleVersion` has to equal the count it
injected. The injection is a command-line argument, so a build that silently stopped applying it
would otherwise produce a DMG carrying `project.yml`'s unmaintained fallback instead — the same Build
for every commit, which is the one thing the number exists not to be.

## Cutting a release by hand

`release.yml` stays off ([Release gate](#release-gate)), so a release is cut from this Mac:

```sh
./Scripts/build-delores-dmg.sh                       # writes build/Delores-<version>.dmg
gh release create v0.2.2 --repo jackdu2333/delores \
  --target "$(git rev-parse HEAD)" --title "Delores 0.2.2" \
  --notes-file build/RELEASE-NOTES-0.2.2.md build/Delores-0.2.2.dmg
```

Three details in that command are not incidental, and two of them fail quietly:

- The Tag is Delores' own number and never a Tinycast one
  ([delores-versioning.md](delores-versioning.md#tags-anchor-a-release)).
- `--target` takes a **full** commit SHA; a short one is rejected. It must name the commit the DMG was
  built from, so the Tag and the artifact's Build describe the same tree.
- The asset name stays ASCII. A non-ASCII prefix is dropped by `gh release create` while the exit
  status stays 0, so the only way to know what was uploaded is to read it back.

```sh
gh api repos/jackdu2333/delores/releases/tags/<tag> --jq '.assets[] | {name, size, state}'
```

The size there has to equal the local file's byte count. Keeping `release.yml` disabled is what keeps
this a download and an archive rather than an update channel — **nothing in the app reads it.**

## CI artifact

`build-app.yml` is how a build reaches this Mac on a machine with no Xcode: it builds the `Delores`
scheme on GitHub's macOS 26 runner and uploads `delores-macos-arm64`, one signed `Delores.zip`.

**It signs with the same identity local builds use, and that is what keeps the Accessibility grant.**
macOS records a TCC grant against the app's *designated requirement*. An identity-signed build's
requirement names the leaf certificate, which every later build reproduces; an ad-hoc build has no
identity, so its requirement is the code hash of those exact bytes — a value the next build cannot
match, and tccd receives an app it has never seen. This lane shipped unsigned for long enough that the
grant had to be given again after every update. It now asserts, before uploading, that the requirement
names a certificate, so that cannot return unnoticed.

Two repository secrets carry the identity: `DELORES_SIGNING_P12_BASE64` and
`DELORES_SIGNING_P12_PASSWORD`. They hold `HuaciGongju CodeSign` — the same identity the local DMG uses,
not `Tinycast Self-Signed`, which belongs to the upstream release lane. Export them as
[signing.md](signing.md) describes for the CI secrets, with these two names and this repository. Export
only to rotate: the identity lives in the login keychain, so the secrets are never regenerated
otherwise. Losing them is therefore survivable; losing the identity costs one final re-grant.

Not overriding the project's own Release settings also means the artifact carries the hardened runtime
and `Tinycast.entitlements`, and `./Scripts/verify-signature.sh` gates it — the same assertion the
release lane runs. **The first identity-signed build still asks for Accessibility once**, because the
copy it replaces was ad-hoc; every update after that keeps the grant.

The lane does override one setting, and it is the same one the local script does: it derives
`CURRENT_PROJECT_VERSION` from `git rev-list --count HEAD`, which is why its checkout fetches full
history. Both channels have to agree here — they install over each other, so a machine updated from a
DMG and then from this artifact must not see the Build move backwards or repeat. The step asserts
afterwards that the count reached the built app, for the reason the local script does.

## Release gate

The inherited `.github/workflows/release.yml` remains in the tree so upstream release improvements
can be merged with a small diff, but its jobs are disabled unless the repository variable
`DELORES_RELEASE_ENABLED` is exactly `true`. Do not enable it until all of these have their own
Delores values:

- GitHub repository and release feed;
- stable, beta and development bundle IDs;
- signing and notarization identity;
- Homebrew cask and install URL;
- updater compatibility and Accessibility/TCC migration policy.

When that decision is made, update this document and the release workflow together. A Tinycast
release is not a valid Delores update even if the binary contains compatible source code.

## Website release gate

`website/` carries Delores' identity now — its own name, repository and subpath, and no link to
upstream's community or funding — but the content behind that identity is not ours yet. It is
**not published**: the repository is private, so Pages is off, and the `deploy` job in
`website.yml` is switched off by the `DELORES_WEBSITE_ENABLED` variable rather than failing. That is
the only reason the list below is not urgent. Every item is a claim about this project that is
currently someone else's:

- **The screenshots and the tour video are of upstream's app, and some show its name in the UI.**
  `backup-import-settings.png` labels a section "Tinycast" and offers to "Restore from a Tinycast
  backup". No amount of copy fixes this: the ten `public/*.png` and `public/delores-in-action.mp4`
  (renamed from `tinycast-in-action.mp4`, but the frames inside are still upstream's) have to be
  recaptured from a Delores build before any of them is shown. This is the one item that cannot be
  worked around.
- **`content/docs/**` and the inherited `docs/*.md` are upstream's prose.** The `Tinycast` in that
  text is a product name, not a reference, so it has to be rewritten page by page — 125 mentions
  under `website/content/docs/` and 249 more across `docs/*.md`. Only the pages made wrong by the
  rename itself (the `.delores` extension, the support directory) were fixed in the code change
  that caused them.
- **The logo wall is off the page.** `companies` in `website/src/data/site.ts` is upstream's list,
  and the section read as an endorsement claim built on other people's trademarks. `LogoWall` is
  not rendered; it needs evidence of its own before it goes back.
- **No community or funding link.** `site.community.discord` and `site.support` are still upstream's
  values and are kept only as a record — every consumer was removed. The Support button was a Polar
  page that paid upstream's author, so a click would have sent a reader's money to the wrong
  project. Delores needs its own, or neither.
- **The inherited app icon.** The mark is another project's artwork. `Tinycast/tinycast.icon` is an
  Icon Composer document holding exactly one asset, `Assets/thunder.svg`, and `project.yml` compiles
  it under `ASSETCATALOG_COMPILER_APPICON_NAME: tinycast` — so a build ships `tinycast.icns` with
  upstream's lightning mark on it, and every size of it. The site's `Logo` is the same shape
  flattened. A Delores mark is a design decision, not a rename.

Nothing above changes the licensing position: the site is a derivative work, the attribution in
`LICENSE` covers it, and not publishing it means the obligations are not yet triggered.
