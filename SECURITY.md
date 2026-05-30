# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.x     | ✅ Yes — security fixes land in the next patch release |
| < 1.0   | ❌ Pre-release, not supported |

## Reporting a vulnerability

If you find a security vulnerability in ccgauge-bar — anything that
could let an attacker read data outside the documented JSONL paths,
escape the app sandbox, write to disk outside `~/Library` (other than
a user-initiated CSV export), or initiate network requests beyond the
ones listed under [Network behaviour in PRIVACY.md](PRIVACY.md#network-behaviour)
— please report it privately so it can be patched before public
disclosure.

**Preferred channel**: open a [private security advisory on
GitHub](https://github.com/chengzuopeng/ccgauge-app/security/advisories/new).

If you can't use GitHub advisories, fall back to a regular issue but
*do not include the exploit details*. The maintainer will reach out
for the technical specifics.

## Scope

In scope:

- Code in `Sources/CCGaugeBar/`
- The packaged `.app` bundle and its `Contents/Info.plist`
- The `.dmg` installer produced by `make dmg`
- The CI / release workflows under `.github/workflows/`

Out of scope:

- Bugs in Apple's Swift / SwiftUI / AppKit frameworks
- Vulnerabilities in macOS itself
- The `ccgauge` npm dashboard (separate project, separate repo)
- Anything triggered by the user manually altering files in
  `~/.claude/projects/` or `~/.codex/sessions/`

## What counts as a vulnerability

- **Yes**: outbound network requests we didn't document; reading files
  outside the documented paths; writing back to user JSONL; arbitrary
  code execution; path traversal; resource exhaustion (memory / CPU
  /disk) triggered by adversarial JSONL input.
- **No**: cosmetic issues, slow first-launch on huge datasets,
  formatting bugs, missing features.

## Response timeline

Best-effort, since this is a personal project:

- Acknowledgement within 7 days
- Triage + impact analysis within 14 days
- Patch release within 30 days for high-severity issues

## Disclosure

After a fix lands in a release, the advisory will be published with
credit to the reporter (unless they prefer otherwise).
