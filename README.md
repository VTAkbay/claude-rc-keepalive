# claude-rc-keepalive

Keep `claude remote-control` running on a Mac so the sessions you drive from the
Claude app (iPhone, claude.ai/code) **stay attached** — through network drops,
Claude Code updates, restarts and reboots.

Out of the box, a background `claude remote-control` loses your sessions in a few
common situations. The app then shows *"Can't reach MacBook"* or *"Remote Control
disconnected"* forever, or the machine appears twice in the environment picker.
This project is a set of small launchd services that prevent that, and repair it
automatically when it happens anyway.

> **Status: unofficial stopgap.** It relies on how Claude Code's remote control
> behaves internally (files, timeouts, server responses), found by reading the
> CLI and by breaking it on purpose. None of that is a documented interface, so
> any Claude Code release can change it. See [Tested with](#tested-with).

## What goes wrong without it

| Situation | What `claude remote-control` does | What you see |
|---|---|---|
| Offline for 10+ minutes (Wi‑Fi drop, captive portal, laptop in a bag) | Gives up, **deletes its environment**, exits with code 0 | Every session: "Can't reach …" forever |
| Supervised with `KeepAlive {SuccessfulExit=false}` | Not restarted after that clean exit | Machine gone until you log in |
| Restarted while its resume pointer is older than 4 hours | Discards the pointer, registers a **new** environment | Sessions orphaned; machine listed twice |
| Restarted with `launchctl kickstart -k` | New process can start before the old one lets go → new environment | Same as above |
| New Claude Code release installed | Keeps running the old binary until restarted | New models/features never show up |
| Restarted within ~3 minutes of the previous bridge for that folder stopping, onto any *other* environment (including a brand-new one) | Server refuses it (HTTP 409 "This folder is already served…"); rc exits after ~1 min and is retried | Machine offline for ~3 minutes |

## What it installs

Three LaunchAgents, per user:

- **remote-control** — `claude remote-control` itself, in the folder you choose,
  restarted on every exit, with a debug log.
- **watchdog** — every 20 s:
  - *freezes* every remote-control process while the network is down (so none of
    them reaches the 10‑minute give-up) and resumes them when it is back;
  - keeps the resume pointer younger than the 4‑hour limit, however long remote
    control is stuck, offline or waiting for a login;
  - if remote control comes back on a new environment anyway, restores the old
    one (retrying through the server's ~3‑minute refusal) and removes the extra one;
  - reattaches any session that ended up detached, using its own
    `claude remote-control --session-id` process from a folder you already trust;
  - merges those back under the main process once everything has been idle for
    15 minutes.
- **updater** — every 30 min runs `claude update`; when a new version is installed
  and every session has been idle for 10 minutes, restarts remote control with a
  plain SIGTERM (which keeps the environment) and verifies the result.

Plus a few commands: `claude-rc-status`, `claude-rc-consolidate`, `claude-rc-deregister`.

## Requirements

- macOS (launchd). Linux/systemd is not supported yet.
- The **native** Claude Code install (`~/.local/bin/claude` → `~/.local/share/claude/versions/…`).
- Command Line Tools (for `python3`): `xcode-select --install`.
- The folder you want to serve must be trusted: run `claude` there once.
- Remote Control enabled once interactively: run `claude remote-control` in a
  terminal, answer `y`, then stop it. A background service cannot answer that prompt.
- Stop any other `claude remote-control` you run for that folder (terminal,
  `screen`, your own LaunchAgent).

## Install

```sh
git clone https://github.com/VTAkbay/claude-rc-keepalive
cd claude-rc-keepalive
./install.sh --dir ~/code          # the folder new sessions start in
```

`--dry-run` shows the generated LaunchAgents without installing anything.
`--prefix com.example.claude-rc` changes the launchd labels.

Check it any time:

```sh
claude-rc-status
```

Uninstall with `./uninstall.sh` (add `--purge` to delete config, state and logs).
Uninstalling stops remote control with SIGTERM, so its environment is kept and a
later reinstall reconnects the same sessions.

## Things worth knowing

- **Captive portals.** Don't let a VPN override DNS on a laptop that joins
  captive-portal Wi‑Fi (coffee shops, hotels): the portal page never loads and
  the Mac has no internet until you switch the VPN off. With Tailscale, run
  `tailscale set --accept-dns=false` and leave "Override DNS servers" off.
- **FileVault.** After a reboot nothing starts until someone logs in at the Mac.
  Sessions survive the wait (the watchdog keeps the pointer valid once it runs),
  but you can't reach the Mac until then. `sudo fdesetup authrestart` avoids it
  for planned reboots.
- **Restarts interrupt a running turn.** That's why the updater waits for idle.
- **`!command` from the phone app is not executed**; it arrives as plain text.

## Troubleshooting

- `claude-rc-status` first. Logs are in `~/Library/Logs/claude-rc-keepalive/`;
  `remote-control.debug.log` records why remote control picked an environment.
- The machine is listed twice and the watchdog hasn't merged it yet (it waits for
  15 idle minutes): run `claude-rc-consolidate` in Terminal.
- A stale extra entry with nothing on it: `claude-rc-deregister env_…`.

## Testing

`tests/fault-stale-pointer` reproduces the "came back on a new environment"
failure on purpose (ages the pointer past 4 hours and restarts remote control)
and checks that the watchdog restores the old environment and removes the extra
one by itself. It interrupts sessions for ~5 minutes.

## Tested with

| Claude Code | macOS | Result |
|---|---|---|
| 2.1.272 – 2.1.283 | 26.x, 27.0 (Apple silicon) | outages, updates, restarts, split/merge — see CHANGELOG |

If a Claude Code release breaks it, please open an issue with
`claude-rc-status` output and the tail of `remote-control.debug.log`.

## License

MIT
