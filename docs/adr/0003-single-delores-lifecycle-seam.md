# ADR 0003: Keep one Delores lifecycle seam and explicit surface admission

- Status: Accepted
- Date: 2026-09-16

## Context

Delores will eventually own more than one Surface. If AppCore exposes one property per Surface,
each upstream Tinycast lifecycle change will touch the product overlay. The first Context Surface
also showed two event hazards: a click on an interactive Delores/Tinycast window could be mistaken
for a selection gesture, and a Quick Action already in progress could cause a newly opened island to
disappear without explanation.

## Decision

AppCore exposes one `DeloresCoordinator`. Its child coordinators remain private to Delores, and
future Surface routing or arbitration stays behind that owner.

The selection monitor ignores only surfaces explicitly marked as selection-blocking that are both
visible and interactive. Ordinary app windows such as Settings stay out of that set, even when their
frames remain visible behind another app. A marked window that sets `ignoresMouseEvents` remains
pass-through, so a HUD or drop guide cannot suppress a valid selection underneath it.

Quick Action entry returns an admission result: `started`, `busy` or `disabled`. A Context Island is
dismissed only after `started`; `busy` keeps the island visible with an explicit status.

## Consequences

The current patch does not introduce a full Surface Router or Result Island. It establishes the
smallest stable lifecycle and event contracts needed before those features arrive, and keeps the
existing Tinycast execution and presentation paths unchanged.
