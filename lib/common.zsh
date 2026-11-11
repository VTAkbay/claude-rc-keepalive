# Shared settings and helpers for claude-rc-keepalive. Sourced by every tool.
umask 077   # state and logs hold session ids and (with --debug-log) conversation text
CONF=${CLAUDE_RC_KEEPALIVE_CONF:-$HOME/.config/claude-rc-keepalive/config}
[[ -f $CONF ]] && source $CONF

: ${LABEL_PREFIX:=com.claude-rc-keepalive}
: ${RC_LABEL:=$LABEL_PREFIX.remote-control}
: ${WD_LABEL:=$LABEL_PREFIX.watchdog}
: ${UP_LABEL:=$LABEL_PREFIX.updater}
: ${CLAUDE:=$HOME/.local/bin/claude}
# macOS ties folder permissions (e.g. access to ~/Documents) to a command-line
# program's path, and every Claude Code update lives at a new path
# (~/.local/share/claude/versions/<v>), so macOS asks again after each update,
# and a remote control restarted overnight waits on that dialog until morning.
# remote control therefore runs from this fixed path: a copy of the current
# version (an APFS clone), refreshed before every restart. Not a hard link: a
# file with several links has one name in the kernel, the link looked up last,
# and macOS identifies the process by that name. `claude update` and a stat of
# the versions folder flipped it to versions/<v>, and the dialog came back.
: ${RC_BIN:=$HOME/.local/share/claude-rc-keepalive/claude}
: ${RESTART_HOURS:=8-22}   # local hours (inclusive) in which the updater may restart rc
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
rc_pids()  { ps -U $(id -u) -o pid=,command= | awk -v CL="$CLAUDE" -v RB="$RC_BIN" '($2==CL || $2==RB) && $3=="remote-control"{print $1}'; }
per_session_pids() { ps -U $(id -u) -o pid=,command= | awk -v CL="$CLAUDE" -v RB="$RC_BIN" '($2==CL || $2==RB) && $3=="remote-control" && $4=="--session-id"{print $1}'; }
sid_pid()  { ps -U $(id -u) -o pid=,command= | awk -v CL="$CLAUDE" -v RB="$RC_BIN" -v S="$1" '($2==CL || $2==RB) && $3=="remote-control" && $4=="--session-id" && $5==S{print $1; exit}'; }
# the executable to start remote control with: the fixed path once installed
rc_exe() { [[ -x $RC_BIN ]] && print -r -- $RC_BIN || print -r -- $CLAUDE; }
# make RC_BIN a copy of the version ~/.local/bin/claude points to (a clone where
# the file system supports it: instant, no extra space; atomic, so a running rc
# keeps its old file)
copy_rc_bin() {
  local v; v=$(readlink "$CLAUDE") || return 1; [[ -f $v ]] || return 1
  { cp -c "$v" "$RC_BIN.tmp" 2>/dev/null || cp "$v" "$RC_BIN.tmp"; } && mv -f "$RC_BIN.tmp" "$RC_BIN"
}
# hash of a binary's code signature: the same for every copy of a build
cdhash() { codesign -dvvv "$1" 2>&1 | awk -F= '/^CDHash=/{print $2; exit}'; }
# version a process runs: from its path, or for the fixed-path copy, by matching
# its signature with the installed versions; empty if the copy was replaced
# under the process (it runs an older version, maybe one already removed)
running_version() {
  local out ino p f h
  out=$(lsof -a -p "$1" -d txt -Fin 2>/dev/null | awk '/^i/{i=substr($0,2)} /^n/{print i" "substr($0,2); exit}')
  [[ -n $out ]] || return 0
  ino=${out%% *}; p=${out#* }
  [[ $p == */claude/versions/* ]] && { print -r -- ${p:t}; return 0; }
  [[ "$(stat -f %i "$p" 2>/dev/null)" == "$ino" ]] || return 0
  h=$(cdhash "$p"); [[ -n $h ]] || return 0
  for f in ${$(readlink "$CLAUDE"):h}/*(N); do [[ "$(cdhash "$f")" == "$h" ]] && { print -r -- ${f:t}; return 0; }; done
}
# is the current local hour inside RESTART_HOURS ("8-22")?
restart_hour_ok() { local h=$(( 10#$(date +%H) )) a=${RESTART_HOURS%-*} b=${RESTART_HOURS#*-}; (( h >= a && h <= b )); }
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
