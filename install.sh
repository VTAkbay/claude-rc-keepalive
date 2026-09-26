#!/bin/zsh
# Install claude-rc-keepalive for the current user (macOS, launchd).
#   ./install.sh --dir ~/code     folder remote control serves (must be trusted in Claude Code)
#       [--prefix com.me.crk]     launchd label prefix (default com.claude-rc-keepalive)
#       [--debug-log]             also keep Claude Code's remote-control debug log (records
#                                 conversation text; useful when something goes wrong)
#       [--dry-run]               show what would be done, change nothing
set -e
umask 077
SRC=${0:A:h}
DIR="" PREFIX_LABEL=com.claude-rc-keepalive DRY=0 DEBUG=0
while (( $# )); do
  case $1 in
    --dir) DIR=${2:A}; shift 2;;
    --prefix) PREFIX_LABEL=$2; shift 2;;
    --debug-log) DEBUG=1; shift;;
    --dry-run) DRY=1; shift;;
    -h|--help) sed -n '2,8p' $0 | sed 's/^# \{0,1\}//'; exit 0;;
    *) print -u2 "unknown option $1"; exit 2;;
  esac
done
die() { print -u2 "✘ $*"; exit 1; }
ok()  { print "✔ $*"; }

[[ $(uname) == Darwin ]] || die "macOS only (launchd). Linux/systemd is not supported yet."
[[ -n "$DIR" && -d "$DIR" ]] || die "--dir <existing folder> is required"
[[ "$PREFIX_LABEL" =~ '^[A-Za-z0-9.-]+$' ]] || die "--prefix may only contain letters, digits, '.' and '-'"
xcode-select -p >/dev/null 2>&1 || die "python3 is needed: install the Command Line Tools first (xcode-select --install)"
CLAUDE=$HOME/.local/bin/claude
[[ "$(readlink $CLAUDE 2>/dev/null)" == $HOME/.local/share/claude/versions/* ]] || die "needs the native Claude Code install (~/.local/bin/claude -> ~/.local/share/claude/versions/...)"
ok "Claude Code $($CLAUDE --version 2>/dev/null | awk '{print $1}') (native)"

cfg=($(python3 - "$DIR" <<'PYEOF'
import json,os,sys
try: d=json.load(open(os.path.expanduser('~/.claude.json')))
except Exception: d={}
p=d.get('projects',{}).get(sys.argv[1],{})
print(int(bool(p.get('hasTrustDialogAccepted'))), int(bool(d.get('remoteDialogSeen'))))
PYEOF
))
[[ ${cfg[1]} == 1 ]] || die "$DIR is not trusted yet: run 'claude' there once and accept the trust prompt"
[[ ${cfg[2]} == 1 ]] || die "run 'claude remote-control' once in a terminal and answer 'y' (a background service cannot answer that prompt)"
ok "$DIR is trusted; Remote Control enabled"

RC_LABEL=$PREFIX_LABEL.remote-control WD_LABEL=$PREFIX_LABEL.watchdog UP_LABEL=$PREFIX_LABEL.updater
PREFIX=$HOME/.local/share/claude-rc-keepalive LOGDIR=$HOME/Library/Logs/claude-rc-keepalive
CONF=$HOME/.config/claude-rc-keepalive/config LA=$HOME/Library/LaunchAgents

# another remote control on this folder would make the server refuse ours
for p in $(ps -U $(id -u) -o pid=,command= | awk '$3=="remote-control"{print $1}'); do
  [[ "$(lsof -a -p $p -d cwd -Fn 2>/dev/null | awk '/^n/{print substr($0,2);exit}')" == "$DIR" ]] || continue
  [[ "$(launchctl print gui/$(id -u)/$RC_LABEL 2>/dev/null | awk '/^\tpid =/{print $3}')" == $p ]] && continue
  die "a 'claude remote-control' (pid $p) already serves $DIR; stop it (and any LaunchAgent or terminal that starts it) first"
done
others=($(grep -l "remote-control" $LA/*.plist 2>/dev/null | grep -v "/$PREFIX_LABEL\." || true))
(( ${#others} )) && print "! other LaunchAgents mention remote-control: ${others:t} (fine if they serve a different folder)"

# PATH for remote control (its sessions run your tools): yours, minus relative entries
RCPATH=${(j.:.)${(M)path:#/*}}

# LaunchAgents are written with plistlib, so no path can break or inject into the XML
mkplists() { python3 $SRC/lib/mkplists.py "$1" "$PREFIX_LABEL" "$CLAUDE" "$DIR" "$HOME" "$RCPATH" "$LOGDIR" "$PREFIX" "$DEBUG"; }

config="RC_DIR=${(q)DIR}
LABEL_PREFIX=${(q)PREFIX_LABEL}"

if (( DRY )); then
  tmp=$(mktemp -d); mkplists $tmp
  print "\nwould install to $PREFIX, config $CONF:\n$config"
  for f in $tmp/*.plist; do print "\n--- $LA/${f:t}"; cat $f; done
  rm -rf $tmp; exit 0
fi

mkdir -p $PREFIX $LOGDIR ${CONF:h} $LA $PREFIX/state; chmod 700 $LOGDIR $PREFIX/state
rm -rf $PREFIX/bin $PREFIX/lib; cp -R $SRC/bin $SRC/lib $PREFIX/; chmod 755 $PREFIX/bin/*
print -r -- $config > $CONF
tmp=$(mktemp -d); mkplists $tmp
for t in remote-control watchdog updater; do
  label=$PREFIX_LABEL.$t
  launchctl bootout gui/$(id -u)/$label 2>/dev/null || true
  plutil -lint -s $tmp/$label.plist; install -m 644 $tmp/$label.plist $LA/$label.plist
  launchctl bootstrap gui/$(id -u) $LA/$label.plist
done
rm -rf $tmp
[[ -d $HOME/.local/bin ]] && for b in $PREFIX/bin/*; do ln -sf $b $HOME/.local/bin/${b:t}; done
ok "installed; logs in $LOGDIR$( (( DEBUG )) && print ' (debug log on)')"
sleep 20; $PREFIX/bin/claude-rc-status
