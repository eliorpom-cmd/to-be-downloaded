# Security Policy

## Supported versions

Only the latest release is supported. The app auto-updates by default, so "the
latest release" is where essentially every install ends up within a day.

## Reporting a vulnerability

**Do not open a public issue.**

Email **eliorpom@gmail.com** with `[TBD security]` in the subject, and include:

- what the flaw is and where (file, endpoint, code path),
- how to reproduce it,
- what an attacker gets out of it.

Expect an acknowledgement within a few days. This is a one-person project, so
please allow reasonable time for a fix before publishing anything.

## What is in scope

- **The update mechanism** — anything that gets unsigned or wrong-signed code
  installed, or that escapes the checks listed in
  [docs/UPDATES.md](docs/UPDATES.md#security-model-of-the-app-updater).
- **The LAN HTTP server** — path traversal in `/api/file/:id`, injection into the
  yt-dlp argument array, anything that turns a request into arbitrary execution
  or into reading files outside the download directory.
- **Subprocess handling** — any way a crafted URL, filename or playlist title
  reaches a shell or escapes its argument slot.
- **Downloaded content** — any path where a hostile server's response leads to
  writing outside the intended directory.

## What is not in scope

- **The LAN server has no authentication, by design.** Anyone on the same
  network can list jobs, start a download and fetch finished files. That is a
  known and deliberate trade-off for a tool meant for a home network. Don't run
  it on a network you don't trust; a report that "anyone on the Wi-Fi can use it"
  will be closed as intended behavior.
- **The app is not sandboxed.** It launches subprocesses and binds a local HTTP
  port, neither of which survives the App Store sandbox. It is signed with a
  Developer ID certificate, notarized, and runs under the hardened runtime; the
  entitlements it does carry are listed in `App/TBD.entitlements` and
  `App/ytdlp.entitlements`, each with the reason it is there. The absence of the
  sandbox is documented rather than a reportable finding — a way to escalate
  through one of those entitlements is very much reportable.
- **Vulnerabilities in yt-dlp or FFmpeg** — report those upstream. If TBD's use
  of them makes an upstream issue exploitable in a way it otherwise wouldn't be,
  that *is* in scope here.
- Anything requiring an attacker who already has local code execution as the
  user.

## Design notes that pre-empt common reports

- Subprocesses are never invoked through a shell — arguments are always passed as
  an array.
- Update archives are Ed25519-verified **before** extraction, extracted with
  `ditto` (never a shell), and nothing from a release is ever executed.
- The updater never escalates privileges. If the app directory isn't writable, it
  stops.
- Update URLs must be HTTPS on a GitHub host, including URLs that came out of an
  API response.
- `--no-check-certificates` is never used. TLS interception is handled by
  building a trust bundle from the system keychain
  ([`TrustStore`](App/Sources/Core/TrustStore.swift)).
