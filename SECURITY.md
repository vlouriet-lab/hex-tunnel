# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest release | ✅ |
| Older releases | ❌ — update to the latest release |

## Reporting a Vulnerability

**Do not open a public Issue for security vulnerabilities.**

Use one of the following private channels:

- **GitHub Security Advisories** — [Report a vulnerability](https://github.com/sota-project/hex-decensor/security/advisories/new) (preferred)
- **Email** — contact the maintainer via the email listed on their GitHub profile

### What to include

1. A clear description of the vulnerability and its impact.
2. Steps to reproduce or a proof-of-concept.
3. Affected versions / components.
4. Any suggested mitigation (optional).

### Process

| Step | Timeline |
|------|----------|
| Acknowledgement | within 48 hours |
| Status update | within 7 days |
| Fix or decision | within 30 days (critical issues — as fast as possible) |

We will credit you in the release notes unless you prefer to remain anonymous.

## Scope

This policy covers:

- The Flutter application code (`lib/`)
- The Android Kotlin bridge (`android/app/src/main/kotlin/`)
- Build scripts and CI configuration

Out of scope:

- Third-party libraries (`libbox.aar` / sing-box) — report upstream to [sagernet/sing-box](https://github.com/sagernet/sing-box/security)
- VPN key sources / remote endpoints

## Notes on VPN Security

This application uses Android's built-in `VpnService` API. Network traffic security depends on the VPN server/key used. The app itself does not store, log, or transmit user traffic.
