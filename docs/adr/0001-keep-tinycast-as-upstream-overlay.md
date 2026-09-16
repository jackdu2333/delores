---
status: accepted
---

# Keep Tinycast as an upstream overlay

Delores keeps Tinycast's source tree, Git history and generated-project conventions intact, and places product-specific behavior under `Tinycast/Features/Delores/`. The integration branch receives upstream through an explicit `upstream` remote and a small set of documented seams; this avoids a whole-tree rename that would make every Tinycast update a permanent merge conflict while preserving the ability to replace or remove a Delores surface later.

The deliberate consequence is that a few internal names may still say Tinycast until a later product-convergence pass. Product identity, bundle IDs and user-facing Delores behavior are changed independently from upstream source provenance.
