# Changelog

## 0.1.3 — 2026-10-20

- Fix: after an overnight update restart, macOS asked for folder access again
  (each Claude Code version lives at a new path, which macOS treats as a new
  program). Remote control waited on the dialog, so nothing ran for 7 hours,
  including scheduled checks. Remote control now runs from a fixed path
  (`~/.local/share/claude-rc-keepalive/claude`, a hard link to the current
  version, moved by the updater before each restart), so macOS asks once. The
  running version is found by matching the file instead of its path.
- The updater only restarts remote control in `RESTART_HOURS` (default 8-22,
  local time), so any dialog appears while someone is around.
- `install.sh --chrome`: gives remote-control sessions Claude in Chrome. Spawned
  sessions don't follow the machine's `/chrome` default.
- Reinstall to switch to the fixed path; the first start may ask for folder
  access once.

## 0.1.2 — 2026-09-27

- Fix: reinstalling with a changed remote-control agent (for example, turning the
  debug log off) could fail with "Bootstrap failed: 5: Input/output error" and stop
  before reloading the watchdog and updater. `launchctl bootout` returns before
  launchd has removed the job, so the installer now waits for that, then retries
  loading.

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
