# Security

## Supported versions

Only the latest release gets security fixes.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through GitHub: [Report a vulnerability](https://github.com/vecvel/coscene/security/advisories/new).

Include what you found, how to reproduce it and what an attacker could do with it. You should hear back within a week. Once a fix is released, the advisory is published with credit to you unless you prefer otherwise.

Areas that matter most:

- Remote level packs: each pack is checked against an Ed25519 signature and a SHA-256 hash before it is used, and every level is re-validated by the engine. A way to get an unsigned or altered pack accepted is a vulnerability.
- Saved progress: stored with the platform's secure storage (Keychain on iOS, encrypted shared preferences on Android).
