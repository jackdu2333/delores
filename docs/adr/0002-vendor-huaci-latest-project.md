# ADR 0002: Vendor the latest Huaci project behind an integration boundary

- Status: Accepted
- Date: 2026-09-16

## Context

The local Huaci project is a Swift Package, while Delores is the Tinycast XcodeGen application.
The latest local Huaci `main` is `463d4f6`, three commits ahead of its GitHub `origin/main`. Those
commits add the companion dock, Ghost hand-off rules, window snap/divider behavior, and their
regression coverage.

The two projects also have independent application entry points and overlapping concepts such as
selection monitoring, LLM configuration, chat messages, settings and transient panels. Copying all
Huaci sources into the Tinycast application target would create duplicate owners and make every
Tinycast upstream update harder to merge.

## Decision

Import the complete latest Huaci project as a squashed Git subtree at
`Integrations/HuaciGongju/`. Preserve its `Package.swift`, standalone resources, source files and
tests so the imported project remains independently verifiable.

The snapshot is an integration source, not a second application entry point inside Delores:

- do not compile Huaci's `AppDelegate` or `main.swift` into the Tinycast target;
- do not route Delores Quick Actions through Huaci's independent LLM service;
- do not start Huaci global monitors merely because Delores starts;
- introduce an explicit adapter and product setting before activating Companion, Spatial or legacy
  Huaci surfaces at runtime.

## Consequences

The latest Huaci code is now versioned inside Delores and its own verification harness runs from the
Delores repository. This preserves the source needed for the next Spatial Surface implementation
without making the current Context Surface depend on a second AI or selection pipeline.

To update the snapshot from the local Huaci checkout:

```sh
git status --short
git subtree pull \
  --prefix=Integrations/HuaciGongju \
  "$HUACI_REPO" main --squash
./Scripts/run-huaci-integration-tests.sh
./Scripts/run-delores-tests.sh
```

Set `HUACI_REPO` to the local Huaci checkout before running the commands.

Resolve conflicts inside the subtree as Huaci-source changes. Resolve conflicts outside the subtree
only through an explicit Delores adapter decision.
