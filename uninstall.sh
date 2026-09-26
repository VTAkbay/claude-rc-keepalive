#!/bin/zsh
# Remove the launchd services and installed tools. Stopping remote control this
# way keeps its environment, so reinstalling later reconnects existing sessions.
#   ./uninstall.sh [--purge]   --purge also deletes config, state and logs
CONF=$HOME/.config/claude-rc-keepalive/config; [[ -f $CONF ]] && source $CONF
LABEL_PREFIX=${LABEL_PREFIX:-com.claude-rc-keepalive}
for t in updater watchdog remote-control; do
  launchctl bootout gui/$(id -u)/$LABEL_PREFIX.$t 2>/dev/null && print "stopped $LABEL_PREFIX.$t"
  rm -f $HOME/Library/LaunchAgents/$LABEL_PREFIX.$t.plist
done
for b in claude-rc-watchdog claude-rc-update claude-rc-status claude-rc-consolidate claude-rc-deregister; do
  [[ "$(readlink $HOME/.local/bin/$b)" == $HOME/.local/share/claude-rc-keepalive/* ]] && rm -f $HOME/.local/bin/$b
done
rm -rf $HOME/.local/share/claude-rc-keepalive/bin $HOME/.local/share/claude-rc-keepalive/lib
if [[ $1 == --purge ]]; then rm -rf $HOME/.config/claude-rc-keepalive $HOME/.local/share/claude-rc-keepalive $HOME/Library/Logs/claude-rc-keepalive; print "purged config, state and logs"; fi
print "done"
