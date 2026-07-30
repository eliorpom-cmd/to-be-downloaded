<!-- Thanks for the PR. Keep it to one subject; see CONTRIBUTING.md. -->

## What this changes

<!-- One or two sentences. Link the issue it addresses: Fixes #123 -->

## Why

<!-- The reasoning, especially if the change is non-obvious. -->

## How it was tested

<!-- Be specific. "Builds" is not testing. Anything network-facing needs a real
     download — CI cannot do that. -->

- [ ] Built and ran on macOS ___ (Apple Silicon)
- [ ] Tested with a real download
- [ ] Tested the LAN web UI, if touched

## Checklist

- [ ] `project.yml` updated and `xcodegen generate` re-run, if files were added
- [ ] No new third-party dependency (or discussed in an issue first)
- [ ] No macOS 14+ API — the deployment target is macOS 13
- [ ] No Swift 6 concurrency warnings
- [ ] Subprocesses still take an argument array, never a shell string
- [ ] `CHANGELOG.md` updated under `Unreleased`, if user-visible
- [ ] Relevant `docs/` page updated, if behavior changed
