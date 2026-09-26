# Shared settings and helpers for claude-rc-keepalive. Sourced by every tool.
umask 077   # state and logs hold session ids and (with --debug-log) conversation text
CONF=${CLAUDE_RC_KEEPALIVE_CONF:-$HOME/.config/claude-rc-keepalive/config}
[[ -f $CONF ]] && source $CONF

: ${LABEL_PREFIX:=com.claude-rc-keepalive}
: ${RC_LABEL:=$LABEL_PREFIX.remote-control}
: ${WD_LABEL:=$LABEL_PREFIX.watchdog}
: ${UP_LABEL:=$LABEL_PREFIX.updater}
: ${CLAUDE:=$HOME/.local/bin/claude}
: ${STATE:=$HOME/.local/share/claude-rc-keepalive/state}
: ${LOGDIR:=$HOME/Library/Logs/claude-rc-keepalive}
: ${RC_DIR:=}

# Claude Code keeps per-folder state in ~/.claude/projects/<path with every
# non-alphanumeric character replaced by '-'>
project_dir() { print -r -- $HOME/.claude/projects/${1//[^A-Za-z0-9]/-}; }
POINTER=$(project_dir "$RC_DIR")/bridge-pointer.json

log()  { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
lpid() { launchctl print "gui/$(id -u)/$1" 2>/dev/null | awk '$1=="pid" && $2=="=" {print $3; exit}'; }
jget() { python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$1" "$2" 2>/dev/null; }
pointer_field() { jget $POINTER $1; }
# pgrep -f misses some of these processes on macOS, so match argv exactly
rc_pids()  { ps -U $(id -u) -o pid=,command= | awk -v CL="$CLAUDE" '$2==CL && $3=="remote-control"{print $1}'; }
per_session_pids() { ps -U $(id -u) -o pid=,command= | awk -v CL="$CLAUDE" '$2==CL && $3=="remote-control" && $4=="--session-id"{print $1}'; }
sid_pid()  { ps -U $(id -u) -o pid=,command= | awk -v CL="$CLAUDE" -v S="$1" '$2==CL && $3=="remote-control" && $4=="--session-id" && $5==S{print $1; exit}'; }
proc_cwd() { lsof -a -p "$1" -d cwd -Fn 2>/dev/null | awk '/^n/{print substr($0,2); exit}'; }
used_cwds() { local p; for p in $(rc_pids); do proc_cwd $p; done; }
write_pointer() { print -r -- "{\"sessionId\":\"${2:-}\",\"environmentId\":\"$1\",\"source\":\"standalone\"}" > $3; }
# Folders we may start a helper `claude remote-control` in (to reattach a
# session, or to deregister an environment). REATTACH_DIRS in the config wins.
# Otherwise: folders the user already trusted in Claude Code (read from
# ~/.claude.json, never written) that carry no project-level Claude config, so
# no project hooks or MCP servers get started behind the user's back.
trusted_dirs() {
  if [[ -n "${REATTACH_DIRS:-}" ]]; then print -rl -- ${=REATTACH_DIRS}; return; fi
  python3 - "$RC_DIR" <<'P'
import json,os,sys
try: d=json.load(open(os.path.expanduser('~/.claude.json')))
except Exception: sys.exit()
home=os.path.expanduser('~')
for k,v in d.get('projects',{}).items():
    if not v.get('hasTrustDialogAccepted') or not os.path.isdir(k) or k in (sys.argv[1],home): continue
    if any(os.path.exists(os.path.join(k,f)) for f in ('.claude/settings.json','.claude/settings.local.json','.mcp.json')): continue
    print(k)
P
}
# keep logs bounded: past 20 MB keep the last 5 MB, in place (launchd holds the fd)
trim_logs() {
  local f; for f in $LOGDIR/*.log(N.Lm+20); do tail -c 5242880 $f > $f.trim && cat $f.trim > $f; rm -f $f.trim; done
}
# sessions.tsv columns: sid env folder('-') quick-exits last-seen-epoch ever-busy(0/1)
REG=$STATE/sessions.tsv
# a session that was ever busy is a real conversation; rc's per-start placeholders never are
env_has_real_sessions() { awk -F'\t' -v E="$1" '$2==E && $6==1{f=1} END{exit !f}' $REG 2>/dev/null; }
# detached from our process group, so launchd restarting us cannot kill it half-way
spawn_detached() {   # log cwd cmd...
  python3 -c 'import subprocess,sys; l=open(sys.argv[1],"ab"); subprocess.Popen(sys.argv[3:],cwd=sys.argv[2],stdin=subprocess.DEVNULL,stdout=l,stderr=l,start_new_session=True)' "$@"
}
need_config() { [[ -n "$RC_DIR" ]] || { print -u2 "claude-rc-keepalive: not configured ($CONF missing). Run install.sh first."; exit 2; }; mkdir -p $STATE $LOGDIR; chmod 700 $STATE $LOGDIR; }
