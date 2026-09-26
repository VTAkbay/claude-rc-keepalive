#!/bin/zsh
# Install claude-rc-keepalive for the current user (macOS, launchd).
#   ./install.sh --dir ~/code            folder remote control serves (must be trusted)
#                [--prefix com.me.claude-rc]   launchd label prefix
#                [--dry-run]             show what would be done, change nothing
set -e
SRC=${0:A:h}
DIR="" PREFIX_LABEL=com.claude-rc-keepalive DRY=0
while (( $# )); do
  case $1 in
    --dir) DIR=${2:A}; shift 2;;
    --prefix) PREFIX_LABEL=$2; shift 2;;
    --dry-run) DRY=1; shift;;
    -h|--help) sed -n '2,6p' $0 | sed 's/^# \{0,1\}//'; exit 0;;
    *) print -u2 "unknown option $1"; exit 2;;
  esac
done
die() { print -u2 "✘ $*"; exit 1; }
ok()  { print "✔ $*"; }

[[ $(uname) == Darwin ]] || die "macOS only (launchd). Linux/systemd is not supported yet."
[[ -n "$DIR" && -d "$DIR" ]] || die "--dir <existing folder> is required"
xcode-select -p >/dev/null 2>&1 || die "python3 is needed: install the Command Line Tools first (xcode-select --install)"
CLAUDE=$HOME/.local/bin/claude
[[ "$(readlink $CLAUDE 2>/dev/null)" == $HOME/.local/share/claude/versions/* ]] || die "needs the native Claude Code install (~/.local/bin/claude -> ~/.local/share/claude/versions/...)"
ok "Claude Code $($CLAUDE --version 2>/dev/null | awk '{print $1}') (native)"

cfg=$(python3 - "$DIR" <<'P'
import json,os,sys
try: d=json.load(open(os.path.expanduser('~/.claude.json')))
except Exception: d={}
p=d.get('projects',{}).get(sys.argv[1],{})
print(int(bool(p.get('hasTrustDialogAccepted'))), int(bool(d.get('remoteDialogSeen'))))
P
)
[[ ${cfg[1]} == 1 ]] || die "$DIR is not trusted yet: run 'claude' there once and accept the trust prompt"
[[ ${cfg[3]} == 1 ]] || die "run 'claude remote-control' once in a terminal and answer 'y' (a background service cannot answer that prompt)"
ok "$DIR is trusted; Remote Control enabled"

RC_LABEL=$PREFIX_LABEL.remote-control WD_LABEL=$PREFIX_LABEL.watchdog UP_LABEL=$PREFIX_LABEL.updater
PREFIX=$HOME/.local/share/claude-rc-keepalive LOGDIR=$HOME/Library/Logs/claude-rc-keepalive
CONF=$HOME/.config/claude-rc-keepalive/config LA=$HOME/Library/LaunchAgents

# another remote control on this folder would make the server refuse ours
for p in $(ps -axo pid=,command= | awk '$3=="remote-control"{print $1}'); do
  [[ "$(lsof -a -p $p -d cwd -Fn 2>/dev/null | awk '/^n/{print substr($0,2);exit}')" == "$DIR" ]] || continue
  [[ "$(launchctl print gui/$(id -u)/$RC_LABEL 2>/dev/null | awk '/^\tpid =/{print $3}')" == $p ]] && continue
  die "a 'claude remote-control' (pid $p) already serves $DIR; stop it (and any LaunchAgent or terminal that starts it) first"
done
others=($(grep -l "remote-control" $LA/*.plist 2>/dev/null | grep -v "/$PREFIX_LABEL\." || true))
(( ${#others} )) && print "! other LaunchAgents mention remote-control: ${others:t} (fine if they serve a different folder)"

render() { sed -e "s|@RC_LABEL@|$RC_LABEL|g; s|@WD_LABEL@|$WD_LABEL|g; s|@UP_LABEL@|$UP_LABEL|g; s|@CLAUDE@|$CLAUDE|g; s|@RC_DIR@|$DIR|g; s|@HOME@|$HOME|g; s|@PATH@|$PATH|g; s|@LOGDIR@|$LOGDIR|g; s|@PREFIX@|$PREFIX|g" $1; }
config="RC_DIR=${(q)DIR}
LABEL_PREFIX=${(q)PREFIX_LABEL}"

if (( DRY )); then
  print "\nwould install to $PREFIX, config $CONF:\n$config"
  for t in remote-control watchdog updater; do print "\n--- $LA/$PREFIX_LABEL.$t.plist"; render $SRC/launchd/$t.plist.in; done
  exit 0
fi

mkdir -p $PREFIX $LOGDIR ${CONF:h} $LA $HOME/.local/share/claude-rc-keepalive/state
rm -rf $PREFIX/bin $PREFIX/lib; cp -R $SRC/bin $SRC/lib $PREFIX/; chmod +x $PREFIX/bin/*
print -r -- $config > $CONF
for t in remote-control watchdog updater; do
  label=$PREFIX_LABEL.$t; plist=$LA/$label.plist
  launchctl bootout gui/$(id -u)/$label 2>/dev/null || true
  render $SRC/launchd/$t.plist.in > $plist; plutil -lint -s $plist
  launchctl bootstrap gui/$(id -u) $plist
done
[[ -d $HOME/.local/bin ]] && for b in $PREFIX/bin/*; do ln -sf $b $HOME/.local/bin/${b:t}; done
ok "installed; logs in $LOGDIR"
sleep 20; $PREFIX/bin/claude-rc-status
