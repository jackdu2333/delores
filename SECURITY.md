# Delores Security Policy

## Reporting a Vulnerability

Report privately through GitHub: **Security** tab → **Report a vulnerability**.

Include your macOS version, the Delores version or commit, reproduction steps, and the impact.
Please don't disclose publicly until it's fixed.

We'll respond as quickly as we can and keep you posted.

## Supported Builds

Delores does not have a public stable or beta release channel configured yet. For a local build,
include the commit SHA and build configuration so the issue can be reproduced.

## Scope

Of particular interest:

- **Accessibility (TCC)** — anything that widens what the paste grant enables.
- **Clipboard history** — text and images cached on disk; unintended exposure or capture.
- **Network** — Delores is offline by default and every networked feature is consent-gated. A path
  that reaches the network without consent, or survives consent being withdrawn, is high severity.
- **Hotkeys** — the in-house hotkey stack and the Input Monitoring grant.
- **Signing and distribution** — the Delores DMG and future distribution chain.

Out of scope: builds being self-signed rather than notarized (known, see
[`docs/signing.md`](docs/signing.md)), and anything needing existing code execution or admin rights on
the machine.
