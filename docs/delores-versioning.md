# Delores versioning

Two numbers, and each answers a question the other cannot.

| Number | Info.plist key | Answers |
| --- | --- | --- |
| **Version** | `CFBundleShortVersionString` | What is this? |
| **Build** | `CFBundleVersion` | Which source produced it? |

**Version 表达「这是什么版本」，Build 表达「这是哪一份源码」。** A version that climbs because
someone built again is the failure this document exists to prevent: `1.0.27` tells a reader nothing
about the product, and it destroys the only thing a version is for.

Both keys already read variables (`$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)`), so nothing in
`Info.plist` has to change as the rules below are applied.

## Which digit moves

Three digits, `MAJOR.MINOR.PATCH`, and each one has a test a reviewer can apply without arguing.

| Move | When | The test |
| --- | --- | --- |
| `1.2.3 → 1.2.4` | Bug fix, performance, small UI adjustment, refactor, docs | **The reader cannot name anything new they can now do.** |
| `1.2.3 → 1.3.0` | A new capability, entry point or workflow | **The reader can point at one thing that was not possible before.** |
| `1.x → 2.0.0` | A generational change | **The Surface table in [delores-architecture.md](delores-architecture.md) changed its rows or their meaning.** |

The last one is deliberately anchored to a line in another document rather than to a feeling. "A
generational change" is unjudgeable and will be relitigated every time; **"the three surfaces changed"
is checkable in one look.** Routine growth of capabilities inside the existing surfaces is MINOR, no
matter how much work it took. Delores is expected to live on MINOR for a long time.

Nothing here is a promise about the size of the diff. A one-line change that adds a Surface is MAJOR;
a thousand-line refactor that adds nothing a reader can see is PATCH.

## Build is the source's serial number

```sh
CURRENT_PROJECT_VERSION = git rev-list --count HEAD
```

Four properties, and each of them is doing work:

- **Monotonic.** A commit can only be added, never inserted before the ones that exist.
- **Reproducible.** Every clone of this repository computes the same number for the same commit. No
  counter to maintain, no machine to ask, no state anywhere.
- **The end of the trace.** A reader who reports a crash has a Build; that Build identifies one commit
  and therefore one tree. `git rev-list --count` is the shortest path from a user's sentence to source.
- **It says which code, not when.** Two builds of one commit share a Build. That is the point, not a
  defect: **the same Build means the same code**, so a bug report that repeats a Build is a bug report
  about something already known.

At `ebdaeaec` this is **678**. It is a count of Delores' own history — this repository's first commit is
`1509d158` (2026-09-16) — so the number is three digits and stays legible rather than inheriting
Tinycast's.

The value is **injected at build time, never hand-written**:

```sh
xcodebuild -project Tinycast.xcodeproj -scheme Delores -configuration Release \
  MARKETING_VERSION="$(...)" \
  CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)"
```

`project.yml` therefore carries `MARKETING_VERSION` as a real source of truth and
`CURRENT_PROJECT_VERSION` only as a fallback for a build that skipped the injection. **Reading the
fallback is a mistake to avoid**, not a value to keep current — it is a number nothing asserts.
[delores-release.md](delores-release.md) says both keys live in `project.yml`; that was true while the
Build was hand-bumped and is now half true. Update it when that file is next touched rather than
leaving two documents disagreeing.

Version is written by a person at release time; Build is derived. **Changing Version is the only edit a
release makes to `project.yml`.**

## Tags anchor a release

```sh
git tag v1.3.0 && git push origin v1.3.0
```

The Tag is the only thing that names a release. The app's own `CFBundleShortVersionString` is what the
Tag is built from, so the two can never disagree — which is also why
`Scripts/build-delores-dmg.sh` names its DMG from the built app rather than from its argument.

This repository currently carries only Tinycast's inherited tags (`v0.9.7`, `v0.9.9-beta.57`, …).
**Delores has no tag of its own yet, and a Delores tag must never be cut on a Tinycast number.**

## Channels are not version suffixes

`alpha` / `beta` / `rc` do not belong in `CFBundleShortVersionString` — Apple's key accepts one to three
period-separated integers and nothing else, so a suffix there is either rejected or silently changes
what the key means. **A pre-release is a channel, not a version**, and upstream already models it that
way in `release.yml`:

```sh
beta)   SUFFIX="-beta.${GITHUB_RUN_NUMBER}"; DISPLAY="Tinycast Beta"; BUNDLE="com.tinycast.app.beta" ;;
stable) SUFFIX="";                           DISPLAY="Tinycast";      BUNDLE="com.tinycast.app" ;;
```

The suffix goes on the **Tag and the release name**; the channel's identity goes on the **bundle ID**,
which is what keeps a beta's preferences, caches and TCC grants from colliding with the stable app's.
Delores already has two channels for the same reason, and an `alpha`/`beta` channel should be a third
bundle ID beside them rather than a suffix in the Version:

| Channel | Bundle ID | Tag | State |
| --- | --- | --- | --- |
| Stable | `com.jackdu.delores` | `v1.3.0` | installed in `/Applications` |
| Development | `com.jackdu.delores.dev` | — | Debug builds only |
| Beta | *undecided* | `v1.3.0-beta.1` | not built |

## Delores and upstream are two version lines

Delores is an overlay on Tinycast, and the two count separately: this line is at `0.2.x` while upstream
is at `0.11.x`. **A Delores version and a Tinycast version must never be compared**, and a reference to
an upstream release carries the word `upstream` to keep them apart — `restore Notes from upstream
v0.11.3-beta.98`, never `v0.11.3-beta.98` on its own.

The two lines are separate, but the **system is shared on purpose**. Upstream's `release.yml` already
ships `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` split exactly this way, and derives
`full_version` from them. Adopting the same split is what keeps merging upstream a small diff: a
second versioning scheme inside this repository would be a second set of meanings for the same two
keys, and the sync workflow would have to reconcile them on every pass.

## What is deliberately not wired yet

Nothing in this document ships a release today. `release.yml` is inherited from upstream but gated off
by the `DELORES_RELEASE_ENABLED` repository variable, and
[delores-release.md](delores-release.md#release-gate) names six things that must exist — with Delores'
own values — before it is turned on.

**The version system is the first of those six, which is the whole reason to fix it now.** Every other
item on that list has to name a version: a release feed publishes them, cases install them, an updater
compares them, and a notarization identity is attached to one. Deciding this late means deciding it
five more times, in five places, none of which agree.

Not yet present, and each will read this document rather than invent its own rule:

- a release feed and GitHub Releases;
- a stable/beta/development bundle ID set (the table above is a start, not a decision);
- a signing and notarization identity;
- a Homebrew cask and install URL;
- updater compatibility, and the Accessibility/TCC migration a version bump has to survive;
- Sparkle, or whatever plays its part.

## Deciding in ten seconds

1. **Can a reader name something they could not do before?** No → PATCH. Yes → MINOR.
2. **Did the Surface table change?** Yes → MAJOR.
3. **Build?** Don't decide it. It is `git rev-list --count HEAD`, computed at build time.
