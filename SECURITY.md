# Security policy

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

- Use GitHub **Private vulnerability reporting** on this repository, or
- Email the maintainer listed on the GitHub profile / `LICENSE`.

Include steps to reproduce, affected platform and version, and impact. You should receive an acknowledgement within a few days.

## Scope

In scope: privilege escalation via packaging helpers, injection of unexpected input events, leakage of typed text through logs or files, insecure default permissions.

Out of scope: issues that require physical access after the user has already granted Input Monitoring / Accessibility / device access, or bugs limited to applications that ignore injected keys.

## Design commitments

- Keystroke history for corrections stays in memory with a bounded size; it is not written to ordinary logs.
- Typed words and clipboard contents are not uploaded and are not stored as analytics.
- Secure input / password fields are skipped when the platform reports them; use Pause for manual control.
- Helper privileges on Linux are limited to selected input devices, not a general root daemon for text.

Details: [docs/security-privacy.md](docs/security-privacy.md) (Russian).
