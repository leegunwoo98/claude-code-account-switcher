# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub Security Advisories instead of opening a public issue.

## Credential model

OAuth tokens are stored in macOS Keychain. The repository, installer, account registry, and usage cache must never contain token values.

If a token appears in a terminal transcript, screenshot, issue, chat, log, or commit, revoke it immediately and generate a replacement.
