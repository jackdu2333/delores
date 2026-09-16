# Delores packaging and release boundary

Delores currently has a local signed packaging path, but no public release channel. This separation
is intentional: a Delores build must never consume Tinycast's release feed, GitHub releases, Homebrew
casks or signing identity by accident.

## Local DMG

On a machine with Xcode 26 and the local signing identity configured:

```sh
./Scripts/build-delores-dmg.sh
./Scripts/build-delores-dmg.sh 0.1.0
```

The script uses the `Delores` scheme from `Tinycast.xcodeproj`, produces `Delores.app`, and writes
`build/Delores-<version>.dmg`. The default local identity is `HuaciGongju CodeSign`; override it for
another machine with `DELORES_CODE_SIGN_IDENTITY`.

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
