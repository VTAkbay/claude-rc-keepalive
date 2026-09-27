# Changelog

## 0.1.1 — 2026-09-27

No change in behaviour.

- `tests/security` skips its repository checks when run outside a git checkout,
  for example from the Homebrew install, and prints the skip message correctly.
- README: says plainly that this is unofficial and not affiliated with Anthropic, and
  cites the Remote Control docs, Claude Code's own logs and the fault test as the
  basis for how it works.

## 0.1.0 — 2026-09-26

First version, extracted from a setup that has run on one Mac since 2026-09-16.
Every mechanism below exists because of a failure that happened there:

- KeepAlive on every exit — remote control exits 0 after it gives up offline.
- Outage freeze — 10‑minute give-up deleted the environment during a 6 h DNS outage.
- Idle-gated SIGTERM updater, no `kickstart -k` — a kickstart restart registered a new environment.
- Pointer freshening — a restart that took effect 9 h later found the pointer past its 4 h limit.
- Guard retry window of 6 min — the server refused the old environment for ~3 min after its owner stopped.
- Per-session keepalive, auto-merge, deregistration of the extra environment — the
  recovery steps that previously had to be run by hand.
- `claude-rc-keepalive` entry command and a Homebrew tap (`vtakbay/tap`).
- Reinstalling leaves an unchanged remote control running (no session interruption on upgrade).
- Security review before release: debug log (conversation text) made opt-in;
  private umask/permissions for state, logs and LaunchAgent output; LaunchAgents
  generated with plistlib (no XML injection through folder names); process
  matching limited to the current user; helper folders exclude projects with
  their own Claude config; deregistration restores the folder's original mode;
  logs capped at 20 MB. `tests/security` covers these.
- Verified by fault injection on 2.1.283 / macOS 27: pointer aged past 4 h + restart
  → rc registered a new environment after ~3 min of 409 refusals → the watchdog
  restored the original one ~3 min later and deregistered the extra one, unattended.
