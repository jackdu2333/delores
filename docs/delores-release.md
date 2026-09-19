# Delores packaging and release boundary

Delores currently has a local signed packaging path, but no public release channel. This separation
is intentional: a Delores build must never consume Tinycast's release feed, GitHub releases, Homebrew
casks or signing identity by accident.

## Local DMG

On a machine with Xcode 26 and the local signing identity configured:

```sh
./Scripts/build-delores-dmg.sh
./Scripts/build-delores-dmg.sh 0.2.0
```

The script uses the `Delores` scheme from `Tinycast.xcodeproj`, produces `Delores.app`, and writes
`build/Delores-<version>.dmg`. The default local identity is `HuaciGongju CodeSign`; override it for
another machine with `DELORES_CODE_SIGN_IDENTITY`.

Run it with no argument and the version is whatever `project.yml` carries — `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` are the one source of truth, currently **0.2.0 / 2**. The argument overrides
`MARKETING_VERSION` for that one build, and the DMG is named from the built app's own
`CFBundleShortVersionString`, so the two can never disagree.

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
